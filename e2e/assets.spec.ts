import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('the register shows each asset with its site, custodian and status', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/assets');
  await expect(page.getByRole('heading', { name: 'Assets' })).toBeVisible();
  const scrubber = page.getByRole('row', { name: /FS-01/ });
  await expect(scrubber).toContainText('Floor scrubber');
  await expect(scrubber).toContainText('Harbour Point – Tower A');
  await expect(scrubber).toContainText('Available');
  const vacuum = page.getByRole('row', { name: /VC-07/ });
  await expect(vacuum).toContainText('Thabo Nkosi');
  await expect(vacuum).toContainText('Assigned');
});

test('a manager registers an asset against a site', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/assets');
  await expect(page.getByRole('button', { name: 'Add' })).toBeDisabled();
  await page.getByLabel('Asset number').fill('PW-02');
  await page.getByLabel('Name').fill('Pressure washer');
  await page.getByLabel('Category').fill('equipment');
  await page.getByLabel('Site').selectOption({ label: 'Northgate Mall – Main Atrium' });
  await page.getByRole('button', { name: 'Add' }).click();

  await expect(page.getByRole('row', { name: /PW-02/ })).toContainText('Northgate Mall – Main Atrium');
  expect(backend.find('assets', { asset_number: 'PW-02' })).toMatchObject({ tenant_id: ID.org, site_id: ID.siteAtrium, status: 'available' });
});

test('assigning an asset records the custodian and the assignment', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/assets');
  await page.getByRole('row', { name: /FS-01/ }).getByRole('button', { name: 'Assign' }).click();
  const dialog = page.getByRole('dialog', { name: 'Assign Floor scrubber' });
  await expect(dialog.getByRole('button', { name: 'Assign asset' })).toBeDisabled();
  await dialog.getByLabel('Employee').fill('Lerato');
  await dialog.getByRole('button', { name: 'Lerato Mahlangu' }).click();
  await dialog.getByLabel('Reason (optional)').fill('Night clean at Tower A');
  await dialog.getByRole('button', { name: 'Assign asset' }).click();

  await expect(page.getByRole('dialog')).toHaveCount(0);
  const row = page.getByRole('row', { name: /FS-01/ });
  await expect(row).toContainText('Lerato Mahlangu');
  await expect(row).toContainText('Assigned');
  expect(backend.find('assets', { id: ID.assetScrubber })).toMatchObject({ status: 'assigned', custodian_employee_id: PERSONAS.employee_two.employeeId });
  expect(backend.table('asset_assignments')).toHaveLength(1);
  expect(backend.table('asset_assignments')[0]).toMatchObject({ assigned_by: PERSONAS.operations_manager.profileId, reason: 'Night clean at Tower A', returned_at: null });
  expect(backend.table('audit_log').some((a) => a.action === 'asset_assigned')).toBe(true);
});

test('returning an asset clears the custodian and closes the assignment', async ({ page, app }) => {
  const backend = await app.open('operations_manager', {
    customize: (t) =>
      t.asset_assignments.push({ id: '00000000-0000-4000-8000-004100000001', tenant_id: ID.org, asset_id: ID.assetVacuum, assigned_to_employee_id: PERSONAS.employee.employeeId, assigned_to_team_id: null, assigned_to_site_id: null, assigned_by: PERSONAS.operations_manager.profileId, assigned_at: '2026-09-01T08:00:00.000Z', returned_at: null, condition_at_assignment: 'fair', condition_at_return: null, reason: null, created_at: '2026-09-01T08:00:00.000Z' }),
  });
  await page.goto('/assets');
  await page.getByRole('row', { name: /VC-07/ }).getByRole('button', { name: 'Return' }).click();

  const row = page.getByRole('row', { name: /VC-07/ });
  await expect(row).toContainText('Available');
  await expect(row).not.toContainText('Thabo Nkosi');
  expect(backend.find('assets', { id: ID.assetVacuum })).toMatchObject({ status: 'available', custodian_employee_id: null });
  expect(backend.find('asset_assignments', { asset_id: ID.assetVacuum }).returned_at).not.toBeNull();
});

test('an asset moves through maintenance, retirement and disposal using only the moves its status allows', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/assets');
  const row = () => page.getByRole('row', { name: /FS-01/ });
  // Available assets cannot be reported damaged/lost from the register: only these moves are offered.
  await expect(row().getByRole('button', { name: 'Report damaged' })).toHaveCount(0);

  await row().getByRole('button', { name: 'Send to maintenance' }).click();
  await expect(row()).toContainText('Maintenance');
  await row().getByRole('button', { name: 'Return to service' }).click();
  await expect(row()).toContainText('Available');
  await row().getByRole('button', { name: 'Retire' }).click();
  await expect(row()).toContainText('Retired');
  await row().getByRole('button', { name: 'Dispose' }).click();
  await expect(row()).toContainText('Disposed');
  expect(backend.find('assets', { id: ID.assetScrubber }).status).toBe('disposed');
});

test('an assigned asset can be reported damaged or lost', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/assets');
  await page.getByRole('row', { name: /VC-07/ }).getByRole('button', { name: 'Report damaged' }).click();
  await expect(page.getByRole('row', { name: /VC-07/ })).toContainText('Damaged');
  expect(backend.find('assets', { id: ID.assetVacuum }).status).toBe('damaged');
});

test('a stale screen cannot force an invalid status change', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/assets');
  await expect(page.getByRole('row', { name: /FS-01/ })).toContainText('Available');
  backend.find('assets', { id: ID.assetScrubber }).status = 'disposed'; // changed elsewhere
  await page.getByRole('row', { name: /FS-01/ }).getByRole('button', { name: 'Send to maintenance' }).click();
  await expect(page.getByRole('alert')).toHaveText('This record cannot move to that status from its current state. Refresh and try again.');
  expect(backend.find('assets', { id: ID.assetScrubber }).status).toBe('disposed');
});

test('employees cannot open the asset register', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/assets');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});
