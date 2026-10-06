import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

// Fixed clock: Monday 2026-09-21 06:00Z. Both fixture shifts run 04:00–12:00Z that day.

test.describe('week schedule', () => {
  test('shows the site\'s roster and the week\'s shifts, and navigates between weeks', async ({ page, app }) => {
    await app.open('supervisor');
    await page.goto('/schedule');
    await expect(page.getByRole('heading', { name: 'Schedule' })).toBeVisible();
    await expect(page.getByLabel('Site')).toHaveValue(ID.siteTowerA);
    await expect(page.getByText('3 employees · 2 scheduled shifts this week')).toBeVisible();
    const thabo = page.getByRole('row', { name: /Thabo Nkosi/ });
    await expect(thabo.getByRole('button', { name: '04:00–12:00' })).toBeVisible();
    await expect(page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: '04:00–12:00' })).toBeVisible();
    await expectNoSeriousViolations(page);

    await page.getByRole('button', { name: 'Next →' }).click();
    await expect(page.getByText('3 employees · 0 scheduled shifts this week')).toBeVisible();
    await page.getByRole('button', { name: 'Today' }).click();
    await expect(page.getByText('2 scheduled shifts this week')).toBeVisible();
  });

  test('a manager creates a shift from a template, which prefills the times', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/schedule');
    await page.getByRole('row', { name: /Sarah van Wyk/ }).getByRole('button', { name: '+ Add' }).nth(2).click(); // Wednesday
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByText('Selected: Sarah van Wyk')).toBeVisible();
    await expect(dialog.getByLabel('Date')).toHaveValue('2026-09-23');
    await dialog.getByLabel('Shift definition').selectOption({ label: 'Night 22:00–06:00 (22:00–06:00)' });
    await expect(dialog.getByLabel('Start time')).toHaveValue('22:00');
    await expect(dialog.getByLabel('End time')).toHaveValue('06:00');
    await expect(dialog.getByLabel('Ends next day (overnight shift)')).toBeChecked();
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);

    const shift = backend.find('shifts', { employee_id: PERSONAS.supervisor.employeeId });
    expect(shift).toMatchObject({ site_id: ID.siteTowerA, shift_definition_id: ID.shiftDefNight, status: 'scheduled', tenant_id: ID.org });
    expect(shift.starts_at).toBe('2026-09-23T22:00:00.000Z');
    expect(shift.ends_at).toBe('2026-09-24T06:00:00.000Z');
    // An overnight shift appears on both calendar days it touches.
    await expect(page.getByRole('row', { name: /Sarah van Wyk/ }).getByRole('button', { name: '22:00–06:00' })).toHaveCount(2);
  });

  test('validation: end must differ from start and an overnight window must be flagged', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/schedule');
    await page.getByRole('row', { name: /Sarah van Wyk/ }).getByRole('button', { name: '+ Add' }).first().click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Start time').fill('10:00');
    await dialog.getByLabel('End time').fill('10:00');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('End time must differ from start time')).toBeVisible();
    await dialog.getByLabel('End time').fill('06:00');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText('Check "Ends next day" for an overnight shift')).toBeVisible();
    expect(backend.table('shifts')).toHaveLength(2);
  });

  test('the database refuses an overlapping shift and the user is told why', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/schedule');
    await page.getByRole('row', { name: /Thabo Nkosi/ }).getByRole('button', { name: '+ Add' }).first().click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Start time').fill('08:00');
    await dialog.getByLabel('End time').fill('10:00');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByRole('alert')).toContainText('This employee already has a shift that overlaps this time.');
    expect(backend.table('shifts').filter((s) => s.employee_id === PERSONAS.employee.employeeId)).toHaveLength(1);
  });

  test('editing a shift to overlap another is refused and changes nothing', async ({ page, app }) => {
    const backend = await app.open('operations_manager', {
      customize: (t) =>
        t.shifts.push({
          id: '00000000-0000-4000-8000-002600000099', tenant_id: ID.org, site_id: ID.siteTowerA, employee_id: PERSONAS.employee.employeeId, supervisor_id: null, shift_definition_id: null,
          starts_at: '2026-09-22T04:00:00.000Z', ends_at: '2026-09-22T12:00:00.000Z', status: 'scheduled', notes: null, created_at: '2026-01-05T08:00:00.000Z', updated_at: '2026-01-05T08:00:00.000Z',
        }),
    });
    await page.goto('/schedule');
    await page.getByRole('row', { name: /Thabo Nkosi/ }).getByRole('button', { name: '04:00–12:00' }).nth(1).click(); // Tuesday
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Date').fill('2026-09-21');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByRole('alert')).toContainText('already has a shift that overlaps');
    expect(backend.find('shifts', { id: '00000000-0000-4000-8000-002600000099' }).starts_at).toBe('2026-09-22T04:00:00.000Z');
  });

  test('a manager edits a shift\'s notes', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/schedule');
    await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: '04:00–12:00' }).click();
    const dialog = page.getByRole('dialog');
    await expect(dialog.getByRole('heading', { name: 'Edit shift' })).toBeVisible();
    await expect(dialog.getByText('Selected: Lerato Mahlangu')).toBeVisible();
    await dialog.getByLabel('Notes').fill('Cover the loading bay');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    expect(backend.find('shifts', { employee_id: PERSONAS.employee_two.employeeId }).notes).toBe('Cover the loading bay');
  });

  test('an employee relieving at this site who is not on its roster still appears', async ({ page, app }) => {
    await app.open('operations_manager', {
      customize: (t) =>
        t.shifts.push({
          id: '00000000-0000-4000-8000-002600000098', tenant_id: ID.org, site_id: ID.siteTowerA, employee_id: PERSONAS.hr_user.employeeId, supervisor_id: null, shift_definition_id: null,
          starts_at: '2026-09-22T06:00:00.000Z', ends_at: '2026-09-22T10:00:00.000Z', status: 'scheduled', notes: null, created_at: '2026-01-05T08:00:00.000Z', updated_at: '2026-01-05T08:00:00.000Z',
        }),
    });
    await page.goto('/schedule');
    await expect(page.getByRole('row', { name: /Hannah Botha/ }).getByRole('button', { name: '06:00–10:00' })).toBeVisible();
  });

  test('roles without scheduling access are redirected', async ({ page, app }) => {
    for (const role of ['hr_user', 'client_user'] as const) {
      await app.open(role);
      await page.goto('/schedule');
      await expect(page).not.toHaveURL(/\/schedule/);
    }
  });

  test('a failed load is reported', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    backend.fault('shifts', { method: 'GET' });
    await page.goto('/schedule');
    await expect(page.getByRole('alert')).toBeVisible();
  });
});

test.describe('shift definitions', () => {
  test('lists templates; a manager adds, edits and archives one; archived ones are not offered when scheduling', async ({ page, app }) => {
    const backend = await app.open('operations_manager');
    await page.goto('/schedule/definitions');
    await expect(page.getByRole('row', { name: /Day 06:00–14:00/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Night 22:00–06:00/ })).toBeVisible();

    await page.getByRole('button', { name: 'Add shift definition' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Name').fill('');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(dialog.getByText(/name is required/i)).toBeVisible();
    await dialog.getByLabel('Name').fill('Afternoon');
    await dialog.getByLabel('Start time').fill('14:00');
    await dialog.getByLabel('End time').fill('22:00');
    await dialog.getByLabel('Break (minutes)').fill('45');
    await dialog.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(page.getByRole('row', { name: /Afternoon/ })).toBeVisible();
    expect(backend.find('shift_definitions', { name: 'Afternoon' })).toMatchObject({ start_time: '14:00', end_time: '22:00', break_minutes: 45, is_overnight: false, status: 'active', tenant_id: ID.org });

    await page.getByRole('row', { name: /Afternoon/ }).getByRole('button', { name: 'Archive' }).click();
    await expect.poll(() => backend.find('shift_definitions', { name: 'Afternoon' }).status).not.toBe('active');
    await page.goto('/schedule');
    await page.getByRole('row', { name: /Sarah van Wyk/ }).getByRole('button', { name: '+ Add' }).first().click();
    await expect(page.getByRole('dialog').getByLabel('Shift definition').locator('option', { hasText: 'Afternoon' })).toHaveCount(0);
  });

  test('read-only roles cannot manage definitions; employees cannot open the page', async ({ page, app }) => {
    await app.open('supervisor');
    await page.goto('/schedule/definitions');
    await expect(page.getByRole('button', { name: 'Add shift definition' })).toHaveCount(0);
    await app.open('employee');
    await page.goto('/schedule/definitions');
    await expect(page).not.toHaveURL(/definitions/);
  });
});

test.describe('my schedule', () => {
  test('an employee sees only their own upcoming shifts with site and status', async ({ page, app }) => {
    await app.open('employee');
    await page.goto('/schedule/mine');
    await expect(page.getByRole('heading', { name: 'My Schedule' })).toBeVisible();
    await expect(page.getByText(/Monday, 21 Sept 2026 · 04:00–12:00/).or(page.getByText(/Monday, 21 Sep 2026 · 04:00–12:00/))).toBeVisible();
    await expect(page.getByText('Harbour Point – Tower A · Scheduled')).toBeVisible();
    await expect(page.locator('p', { hasText: ' · 04:00–12:00' })).toHaveCount(1);
  });

  test('cancelled shifts are not listed and an empty schedule says so', async ({ page, app }) => {
    await app.open('employee', { customize: (t) => t.shifts.forEach((s) => (s.status = 'cancelled')) });
    await page.goto('/schedule/mine');
    await expect(page.getByText('No upcoming shifts scheduled.')).toBeVisible();
  });

  test('an account with no employee record is told so', async ({ page, app }) => {
    await app.open('organization_administrator', { customize: (t) => (t.employees = t.employees.filter((e) => e.profile_id !== PERSONAS.organization_administrator.profileId)) });
    await page.goto('/schedule/mine');
    await expect(page.getByText('No employee record is linked to your account')).toBeVisible();
  });
});
