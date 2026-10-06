import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS, dateOffset } from './utils/sebetsaFixtures';

const WINDOW = '00000000-0000-4000-8000-005000000001';
const withWindow = (employeeId: string | null) => (t: Record<string, Record<string, unknown>[]>) =>
  t.employee_availability.push({ id: WINDOW, tenant_id: ID.org, employee_id: employeeId, day_of_week: 1, start_time: '06:00:00', end_time: '14:00:00', created_at: '2026-01-05T08:00:00.000Z', updated_at: '2026-01-05T08:00:00.000Z' });

test('an employee manages their own weekly availability', async ({ page, app }) => {
  const backend = await app.open('employee', { customize: withWindow(PERSONAS.employee.employeeId) });
  await page.goto('/schedule/availability');
  await expect(page.getByRole('heading', { name: 'Availability' })).toBeVisible();
  const monday = page.locator('div', { hasText: /^Monday/ }).filter({ has: page.getByText('06:00–14:00') }).first();
  await expect(monday).toBeVisible();
  await expect(page.getByText('Unavailable', { exact: true })).toHaveCount(6);

  await page.getByLabel('Add window').selectOption('3');
  await page.getByLabel('Start', { exact: true }).fill('09:00');
  await page.getByLabel('End', { exact: true }).fill('13:00');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.getByText('09:00–13:00')).toBeVisible();
  expect(backend.find('employee_availability', { day_of_week: 3 })).toMatchObject({ employee_id: PERSONAS.employee.employeeId, tenant_id: ID.org, start_time: '09:00', end_time: '13:00' });

  await page.getByRole('button', { name: 'Remove Monday 06:00-14:00' }).click();
  await expect(page.getByText('06:00–14:00')).toHaveCount(0);
  expect(backend.table('employee_availability').some((w) => w.id === WINDOW)).toBe(false);
  await expectNoSeriousViolations(page);
});

test('a window must end after it starts', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/schedule/availability');
  await page.getByLabel('Start', { exact: true }).fill('15:00');
  await page.getByLabel('End', { exact: true }).fill('09:00');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.getByText('End time must be after start time')).toBeVisible();
  expect(backend.table('employee_availability')).toHaveLength(0);
});

test('exceptions: a day off and a narrower window, with reasons, and removal', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/schedule/availability');
  await expect(page.getByText('No upcoming exceptions.')).toBeVisible();

  await page.getByRole('button', { name: 'Add exception' }).click();
  await expect(page.getByText('Date is required')).toBeVisible();

  await page.getByLabel('Date').fill(dateOffset(5));
  await page.getByLabel('Reason (optional)').fill('Clinic appointment');
  await page.getByRole('button', { name: 'Add exception' }).click();
  await expect(page.getByText('Unavailable all day · Clinic appointment')).toBeVisible();
  expect(backend.find('employee_availability_exceptions', { exception_date: dateOffset(5) })).toMatchObject({ is_available: false, employee_id: PERSONAS.employee.employeeId });

  await page.getByLabel('Date').fill(dateOffset(6));
  await page.getByLabel('Availability').selectOption('true');
  await page.getByLabel('Start (optional)').fill('10:00');
  await page.getByLabel('End (optional)').fill('12:00');
  await page.getByRole('button', { name: 'Add exception' }).click();
  await expect(page.getByText('Available 10:00–12:00 only')).toBeVisible();

  await page.getByRole('button', { name: 'Remove', exact: true }).first().click();
  await expect(page.getByText('Unavailable all day · Clinic appointment')).toHaveCount(0);
  expect(backend.table('employee_availability_exceptions')).toHaveLength(1);
});

test('a manager searches for an employee and manages their availability, then returns to their own', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/schedule/availability');
  await expect(page.getByText('Currently viewing: Omar Mokoena')).toBeVisible();
  await page.getByLabel('Manage availability for').fill('Thabo');
  await page.getByRole('button', { name: /Thabo Nkosi/ }).click();
  await expect(page.getByText('Currently viewing: Thabo Nkosi')).toBeVisible();
  await page.getByLabel('Start', { exact: true }).fill('07:00');
  await page.getByLabel('End', { exact: true }).fill('15:00');
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.getByText('07:00–15:00')).toBeVisible();
  expect(backend.find('employee_availability', { start_time: '07:00' }).employee_id).toBe(PERSONAS.employee.employeeId);

  await page.getByRole('button', { name: '← Back to my own availability' }).click();
  await expect(page.getByText('Currently viewing: Omar Mokoena')).toBeVisible();
  await expect(page.getByText('07:00–15:00')).toHaveCount(0);
});

test('failures are reported and a failed add keeps nothing', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/schedule/availability');
  backend.fault('employee_availability', { method: 'POST', times: 1 });
  await page.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.getByText('Failed to add availability window.')).toBeVisible();
  expect(backend.table('employee_availability')).toHaveLength(0);
});

test('a failure while searching employees is shown', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/schedule/availability');
  await expect(page.getByText('Currently viewing: Omar Mokoena')).toBeVisible();
  backend.fault('employees', { method: 'GET', times: 1 });
  await page.getByLabel('Manage availability for').fill('Tha');
  await expect(page.getByText('Failed to search employees.')).toBeVisible();
});

test('roles without availability management cannot search for others', async ({ page, app }) => {
  await app.open('supervisor');
  await page.goto('/schedule/availability');
  await expect(page.getByLabel('Manage availability for')).toHaveCount(0);
});

test('an account without an employee record is told so', async ({ page, app }) => {
  await app.open('employee', { customize: (t) => (t.employees = t.employees.filter((e) => e.profile_id !== PERSONAS.employee.profileId)) });
  await page.goto('/schedule/availability');
  await expect(page.getByText('No employee record is linked to your account')).toBeVisible();
});
