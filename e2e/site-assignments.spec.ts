import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS, TODAY } from './utils/sebetsaFixtures';

test('lists current assignments with names, sites and roles; filters by site and by history', async ({ page, app }) => {
  await app.open('operations_manager', {
    customize: (t) =>
      t.site_assignments.push({
        id: '00000000-0000-4000-8000-002400000099', tenant_id: ID.org, site_id: ID.siteAtrium, employee_id: PERSONAS.employee_two.employeeId, role_on_site: 'Cleaner',
        start_date: '2025-01-01', end_date: '2025-06-30', created_at: '2025-01-01T00:00:00Z', updated_at: '2025-01-01T00:00:00Z',
      }),
  });
  await page.goto('/site-assignments');
  await expect(page.getByRole('heading', { name: 'Site Assignments' })).toBeVisible();
  await expect(page.getByRole('row', { name: /Thabo Nkosi.*Harbour Point – Tower A.*Cleaner.*2025-03-03/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Sarah van Wyk.*Supervisor/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Main Atrium/ })).toHaveCount(0); // ended — historical only

  await page.getByLabel('Filter by current/historical').selectOption('historical');
  await expect(page.getByRole('row', { name: /Lerato Mahlangu.*Main Atrium.*2025-06-30/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Thabo Nkosi/ })).toHaveCount(0);

  await page.getByLabel('Filter by current/historical').selectOption('');
  await page.getByLabel('Filter by site').selectOption(ID.siteAtrium);
  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ })).toBeVisible();
  await expect(page.getByRole('row', { name: /Thabo Nkosi/ })).toHaveCount(0);
  await expectNoSeriousViolations(page);
});

test('a manager assigns an employee to a site, with validation', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/site-assignments');
  await page.getByRole('button', { name: 'Assign employee' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog.getByText('Site is required')).toBeVisible();
  await expect(dialog.getByText('Employee is required')).toBeVisible();
  await expect(dialog.getByText('Start date is required')).toBeVisible();

  await dialog.getByLabel('Site', { exact: false }).first().selectOption(ID.siteAtrium);
  await dialog.getByLabel('Employee', { exact: false }).first().fill('Hannah');
  await dialog.getByRole('button', { name: /Hannah Botha/ }).click();
  await dialog.getByLabel('Role on site').fill('Reception cover');
  await dialog.getByLabel('Start date').fill('2026-09-22');
  await dialog.getByLabel('End date').fill('2026-09-01');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog.getByText('End date must be on or after the start date')).toBeVisible();

  await dialog.getByLabel('End date').fill('');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.getByLabel('Filter by site').selectOption(ID.siteAtrium);
  await expect(page.getByRole('row', { name: /Hannah Botha.*Main Atrium.*Reception cover.*2026-09-22/ })).toBeVisible();
  expect(backend.find('site_assignments', { role_on_site: 'Reception cover' })).toMatchObject({ employee_id: PERSONAS.hr_user.employeeId, site_id: ID.siteAtrium, end_date: null, tenant_id: ID.org });
});

test('ending an assignment stamps today and removes the End action; editing changes the role', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/site-assignments');
  const thabo = page.getByRole('row', { name: /Thabo Nkosi/ });
  await thabo.getByRole('button', { name: 'Edit' }).click();
  await expect(page.getByRole('dialog').getByText('Selected: Thabo Nkosi')).toBeVisible();
  await page.getByRole('dialog').getByLabel('Role on site').fill('Lead cleaner');
  await page.getByRole('dialog').getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('row', { name: /Thabo Nkosi.*Lead cleaner/ })).toBeVisible();

  await page.getByRole('row', { name: /Thabo Nkosi/ }).getByRole('button', { name: 'End' }).click();
  // Ending today keeps the person assigned through today, so the row stays until tomorrow — now with an end date.
  await expect(page.getByRole('row', { name: /Thabo Nkosi.*Lead cleaner/ })).toContainText(TODAY);
  await expect(page.getByRole('row', { name: /Thabo Nkosi/ }).getByRole('button', { name: 'End' })).toHaveCount(0);
  expect(backend.find('site_assignments', { employee_id: PERSONAS.employee.employeeId, site_id: ID.siteTowerA })).toMatchObject({ end_date: TODAY, role_on_site: 'Lead cleaner' });
});

test('a failure while ending an assignment is shown and nothing changes', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/site-assignments');
  backend.fault('site_assignments', { method: 'PATCH', times: 1 });
  await page.getByRole('row', { name: /Thabo Nkosi/ }).getByRole('button', { name: 'End' }).click();
  await expect(page.getByText('Failed to end site assignment.')).toBeVisible();
  expect(backend.find('site_assignments', { employee_id: PERSONAS.employee.employeeId }).end_date).toBeNull();
});

test('a failure resolving employee names is shown', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  backend.fault('employees', { method: 'GET' });
  await page.goto('/site-assignments');
  await expect(page.getByText('Failed to load employee names.')).toBeVisible();
});

test('HR and site managers can view assignments; HR cannot change them', async ({ page, app }) => {
  await app.open('hr_user');
  await page.goto('/site-assignments');
  await expect(page.getByRole('row', { name: /Thabo Nkosi/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Assign employee' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'End' })).toHaveCount(0);
});

test('employees cannot open site assignments', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/site-assignments');
  await expect(page).not.toHaveURL(/site-assignments/);
});
