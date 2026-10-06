import { test, expect } from './utils/test';
import { ID, PERSONAS, TODAY, dateOffset } from './utils/sebetsaFixtures';

const THABO_RECORD = '00000000-0000-4000-8000-002800000001';

test('employee clocks in against today\'s shift, takes a break and clocks out', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/attendance/mine');
  await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
  await expect(page.getByText('You are not clocked in.')).toBeVisible();
  await expect(page.getByText(/Today's shift: .*–/)).toBeVisible();

  await page.getByRole('button', { name: 'Clock in' }).click();
  await expect(page.getByText(/Clocked in at/)).toBeVisible();
  const record = backend.find('attendance_records', { id: THABO_RECORD });
  expect(record.clock_in_at).not.toBeNull();
  expect(record.recorded_by).toBe(PERSONAS.employee.profileId);

  await page.getByRole('button', { name: 'Start break' }).click();
  await expect(page.getByText(/On break since/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Clock out' })).toBeDisabled();
  await page.getByRole('button', { name: 'End break' }).click();
  await expect(page.getByText(/On break since/)).toHaveCount(0);

  await page.getByRole('button', { name: 'Clock out' }).click();
  await expect(page.getByText('You are not clocked in.')).toBeVisible();
  expect(backend.find('attendance_records', { id: THABO_RECORD }).clock_out_at).not.toBeNull();
  expect(backend.table('attendance_breaks')).toHaveLength(1);
  expect(backend.table('audit_log').filter((a) => String(a.action).startsWith('attendance_clock_'))).toHaveLength(2);
});

test('clocking in two hours after the shift started is recorded as late, using the tenant policy', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/attendance/mine');
  await page.getByRole('button', { name: 'Clock in' }).click();

  await expect(page.getByText('Late', { exact: true })).toBeVisible();
  // Shift starts 06:00 SAST, "now" is 08:00 SAST, 5-minute grace: 115 minutes late.
  expect(backend.find('attendance_records', { id: THABO_RECORD })).toMatchObject({ status: 'late', late_minutes: 115 });
});

test('a second device clocking in first is reported as an error, never a duplicate record', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/attendance/mine');
  await expect(page.getByText('You are not clocked in.')).toBeVisible();

  // Meanwhile the employee clocked in from another device.
  backend.find('attendance_records', { id: THABO_RECORD }).clock_in_at = '2026-09-21T05:00:00.000Z';

  await page.getByRole('button', { name: 'Clock in' }).click();
  await expect(page.getByRole('alert')).toHaveText('You are already clocked in.');
  expect(backend.table('attendance_records').filter((r) => r.employee_id === PERSONAS.employee.employeeId)).toHaveLength(1);
});

test('clock-in is refused, with an explanation, when no shift or home site is known', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) => {
      t.shifts = [];
      t.attendance_records = [];
      const e = t.employees.find((x) => x.id === PERSONAS.employee.employeeId);
      if (e) e.home_site_id = null;
    },
  });
  await page.goto('/attendance/mine');
  await page.getByRole('button', { name: 'Clock in' }).click();

  await expect(page.getByRole('alert')).toContainText('no shift or home site assigned');
  expect(backend.requests.filter((r) => r.rpc === 'clock_in')).toEqual([]);
});

test('a clock-in failure is shown and nothing is recorded', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('rpc:clock_in', { status: 500, message: 'database unavailable' });
  await page.goto('/attendance/mine');
  await page.getByRole('button', { name: 'Clock in' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  expect(backend.find('attendance_records', { id: THABO_RECORD }).clock_in_at).toBeNull();
});

test('requesting a correction needs the right time and a reason, and queues it for review', async ({ page, app }) => {
  const backend = await app.open('employee', {
    customize: (t) => {
      const r = t.attendance_records.find((x) => x.id === THABO_RECORD);
      if (r) Object.assign(r, { clock_in_at: '2026-09-21T05:30:00.000Z', status: 'late', late_minutes: 85 });
    },
  });
  await page.goto('/attendance/mine');
  await page.getByRole('button', { name: 'Request a correction' }).click();
  await expect(page.getByRole('button', { name: 'Submit request' })).toBeDisabled();

  await page.getByLabel('Reason for correction').fill('Biometric reader was down; I arrived at 06:00');
  await expect(page.getByRole('button', { name: 'Submit request' })).toBeDisabled();
  await page.getByLabel('Correct clock-in time').fill('2026-09-21T06:00');
  await page.getByRole('button', { name: 'Submit request' }).click();

  await expect(page.getByRole('button', { name: 'Request a correction' })).toBeVisible();
  const correction = backend.table('attendance_corrections')[0];
  expect(correction).toMatchObject({ field: 'clock_in_at', status: 'pending', requested_by: PERSONAS.employee.profileId, reason: 'Biometric reader was down; I arrived at 06:00' });
  expect(correction.new_value).toBe(new Date('2026-09-21T06:00').toISOString()); // the time the employee typed, in their local zone
});

test('a manager approves a correction and the attendance record is updated', async ({ page, app }) => {
  const backend = await app.open('site_manager', {
    customize: (t) =>
      t.attendance_corrections.push({
        id: '00000000-0000-4000-8000-002900000001', tenant_id: ID.org, attendance_record_id: THABO_RECORD, field: 'clock_in_at', previous_value: null,
        new_value: '2026-09-21T04:00:00.000Z', reason: 'Forgot to clock in on time', status: 'pending', requested_by: PERSONAS.employee.profileId,
        reviewed_by: null, reviewed_at: null, review_notes: null, created_at: '2026-09-21T05:00:00.000Z', updated_at: '2026-09-21T05:00:00.000Z',
      }),
  });
  await page.goto('/attendance/corrections');
  await expect(page.getByText('Forgot to clock in on time')).toBeVisible();
  await page.getByLabel('Review notes').fill('Verified against CCTV log');
  await page.getByRole('button', { name: 'Approve' }).click();

  await expect(page.getByText('No pending correction requests.')).toBeVisible();
  expect(backend.find('attendance_corrections', { id: '00000000-0000-4000-8000-002900000001' })).toMatchObject({ status: 'approved', reviewed_by: PERSONAS.site_manager.profileId, review_notes: 'Verified against CCTV log' });
  expect(backend.find('attendance_records', { id: THABO_RECORD }).clock_in_at).toBe('2026-09-21T04:00:00.000Z');
});

test('a manager cannot approve a correction that concerns their own attendance', async ({ page, app }) => {
  const sarahRecord = '00000000-0000-4000-8000-002800000099';
  const backend = await app.open('supervisor', {
    customize: (t) => {
      t.attendance_records.push({ id: sarahRecord, tenant_id: ID.org, shift_id: null, site_id: ID.siteTowerA, employee_id: PERSONAS.supervisor.employeeId, status: 'present', clock_in_at: '2026-09-21T04:30:00.000Z', clock_out_at: null, recorded_by: PERSONAS.supervisor.profileId, notes: null, created_at: '2026-09-21T04:30:00.000Z', updated_at: '2026-09-21T04:30:00.000Z', late_minutes: null, early_departure_minutes: null, worked_minutes: null, overtime_minutes: null });
      t.attendance_corrections.push({ id: '00000000-0000-4000-8000-002900000002', tenant_id: ID.org, attendance_record_id: sarahRecord, field: 'clock_in_at', previous_value: null, new_value: '2026-09-21T04:00:00.000Z', reason: 'My own correction', status: 'pending', requested_by: PERSONAS.supervisor.profileId, reviewed_by: null, reviewed_at: null, review_notes: null, created_at: '2026-09-21T05:00:00.000Z', updated_at: '2026-09-21T05:00:00.000Z' });
    },
  });
  await page.goto('/attendance/corrections');
  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('attendance_corrections', { id: '00000000-0000-4000-8000-002900000002' }).status).toBe('pending');
});

test('an employee cannot open the corrections queue', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/attendance/corrections');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('supervisor marks the site roster: statuses are saved once per person and re-saving updates instead of duplicating', async ({ page, app }) => {
  const backend = await app.open('supervisor', { customize: (t) => (t.attendance_records = []) });
  await page.goto('/attendance');
  await page.locator('#attendance-site').selectOption(ID.siteTowerA);
  await expect(page.getByRole('row', { name: /Thabo Nkosi/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Sarah van Wyk/ })).toBeVisible();

  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Absent' }).click();
  await page.getByRole('button', { name: 'Save attendance' }).click();
  await expect(page.getByText('Attendance saved.')).toBeVisible();

  const rows = () => backend.table('attendance_records').filter((r) => r.site_id === ID.siteTowerA);
  expect(rows()).toHaveLength(3);
  expect(rows().find((r) => r.employee_id === PERSONAS.employee_two.employeeId)?.status).toBe('absent');
  expect(rows().every((r) => r.recorded_by === PERSONAS.supervisor.profileId)).toBe(true);

  // Change one status and save again: still three records.
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Late' }).click();
  await page.getByRole('button', { name: 'Save attendance' }).click();
  await expect(page.getByText('Attendance saved.')).toBeVisible();
  expect(rows()).toHaveLength(3);
  expect(rows().find((r) => r.employee_id === PERSONAS.employee_two.employeeId)?.status).toBe('late');

  // Saving without changes again does not create anything either.
  await page.getByRole('button', { name: 'Save attendance' }).click();
  await expect(page.getByText('Attendance saved.')).toBeVisible();
  expect(rows()).toHaveLength(3);
});

test('attendance marked for a past date is recorded on that date, not today', async ({ page, app }) => {
  const backend = await app.open('supervisor', { customize: (t) => (t.attendance_records = []) });
  const past = dateOffset(-2);
  await page.goto('/attendance');
  await page.locator('#attendance-site').selectOption(ID.siteTowerA);
  await page.locator('#attendance-date').fill(past);
  await expect(page.getByRole('row', { name: /Thabo Nkosi/ })).toBeVisible();
  await page.getByRole('button', { name: 'Save attendance' }).click();
  await expect(page.getByText('Attendance saved.')).toBeVisible();

  const saved = backend.table('attendance_records');
  expect(saved.length).toBeGreaterThan(0);
  expect(saved.every((r) => String(r.created_at).startsWith(past) || String(r.created_at).startsWith(dateOffset(-3)))).toBe(true);
  expect(saved.some((r) => String(r.created_at).startsWith(TODAY))).toBe(false);
});

test('an employee cannot mark the site roster', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/attendance');
  await expect(page.getByRole('button', { name: 'Save attendance' })).toHaveCount(0);
});
