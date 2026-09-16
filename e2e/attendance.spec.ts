import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildProfileRow,
  buildEmployeeRow,
  buildShiftRow,
  buildAttendanceRecordRow,
  buildAttendanceCorrectionRow,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/** Genuine Sebetsa Phase I — Attendance & Time E2E coverage, built on the
 * same real session/table/role foundation established for Leave (Phase H).
 * Real UI, mocked REST/RPC — no database-internal state asserted here;
 * that belongs to supabase/rls-tests/attendance_time_management.sql. */

test('employee can clock in, take a break, and clock out', async ({ page, context }) => {
  // MyAttendancePage reads a device location before clock-in/out and passes
  // it to clock_in()/clock_out() — grant + mock it so the test resolves
  // instantly from Playwright's injected position instead of the browser's
  // real network location provider (which this sandbox's egress policy
  // blocks, not a product defect).
  await context.grantPermissions(['geolocation']);
  await context.setGeolocation({ latitude: -26.2041, longitude: 28.0473 });

  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow({ home_site_id: 'site-1' }),
    shifts: [buildShiftRow()],
    attendanceRecords: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'clock_in') {
        const record = buildAttendanceRecordRow({ clock_in_at: new Date().toISOString(), status: 'present' });
        state.attendanceRecords = [record];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(record) });
        return true;
      }
      if (fnName === 'start_break') {
        const brk = { id: 'break-1', tenant_id: state.employee?.tenant_id, attendance_record_id: payload.p_attendance_record_id, break_start: new Date().toISOString(), break_end: null };
        state.attendanceBreaks = [brk];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(brk) });
        return true;
      }
      if (fnName === 'end_break') {
        const brk = { ...(state.attendanceBreaks?.[0] ?? {}), break_end: new Date().toISOString() };
        state.attendanceBreaks = [];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(brk) });
        return true;
      }
      if (fnName === 'clock_out') {
        const record = { ...(state.attendanceRecords?.[0] ?? buildAttendanceRecordRow()), clock_out_at: new Date().toISOString(), worked_minutes: 480 };
        state.attendanceRecords = [record];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(record) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/attendance/mine');
  await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
  await expect(page.getByText('You are not clocked in.')).toBeVisible();

  await page.getByRole('button', { name: 'Clock in' }).click();
  await expect(page.getByText(/Clocked in at/)).toBeVisible();

  await page.getByRole('button', { name: 'Start break' }).click();
  await expect(page.getByText(/On break since/)).toBeVisible();

  await page.getByRole('button', { name: 'End break' }).click();
  await expect(page.getByText(/On break since/)).toHaveCount(0);

  await page.getByRole('button', { name: 'Clock out' }).click();
  await expect(page.getByText("You are not clocked in.")).toBeVisible();
});

test('employee cannot clock out while a break is open (button disabled)', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    attendanceRecords: [buildAttendanceRecordRow({ clock_in_at: new Date().toISOString() })],
    attendanceBreaks: [{ id: 'break-1', tenant_id: 'x', attendance_record_id: 'attendance-1', break_start: new Date().toISOString(), break_end: null }],
  });

  await page.goto('/attendance/mine');
  await expect(page.getByText(/On break since/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Clock out' })).toBeDisabled();
});

test('employee can request an attendance correction', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    attendanceRecords: [buildAttendanceRecordRow({ clock_in_at: new Date().toISOString() })],
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'request_attendance_correction') {
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(buildAttendanceCorrectionRow()) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/attendance/mine');
  await page.getByRole('button', { name: 'Request a correction' }).click();
  await page.getByLabel('Reason for correction').fill('Forgot to clock in on time');
  await page.getByRole('button', { name: 'Submit request' }).click();
  await expect(page.getByRole('button', { name: 'Request a correction' })).toBeVisible();
});

test('organization_administrator can approve a pending attendance correction', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  const pending = buildAttendanceCorrectionRow();
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    attendanceCorrections: [pending],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'decide_attendance_correction') {
        const decided = { ...pending, status: 'approved', reviewed_by: '11111111-1111-1111-1111-111111111111', review_notes: payload.p_review_notes ?? null };
        state.attendanceCorrections = [decided];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(decided) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/attendance/corrections');
  await expect(page.getByRole('heading', { name: 'Attendance Corrections' })).toBeVisible();
  await expect(page.getByText('Forgot to clock in on time')).toBeVisible();

  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByText('No pending correction requests.')).toBeVisible();
});

test('an employee is blocked from the Attendance Corrections queue', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/attendance/corrections');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('My Attendance has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow() });
  await page.goto('/attendance/mine');
  await expect(page.getByRole('heading', { name: 'My Attendance' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Attendance Corrections has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    attendanceCorrections: [buildAttendanceCorrectionRow()],
  });
  await page.goto('/attendance/corrections');
  await expect(page.getByRole('heading', { name: 'Attendance Corrections' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
