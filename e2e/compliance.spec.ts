import { test, expect } from './utils/test';
import { ID, PERSONAS, dateOffset } from './utils/sebetsaFixtures';

test('a manager defines a requirement and starts tracking it for a site', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/compliance');
  await expect(page.getByRole('button', { name: 'Add' })).toBeDisabled();
  await page.getByLabel('Name').fill('Chemical storage inspection');
  await page.getByLabel('Category').fill('safety');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('Chemical storage inspection')).toBeVisible();
  expect(backend.find('compliance_requirements', { name: 'Chemical storage inspection' })).toMatchObject({ tenant_id: ID.org, created_by: PERSONAS.operations_manager.profileId, applies_to_scope: 'site' });

  await page.getByLabel('Site for Chemical storage inspection').selectOption({ label: 'Harbour Point – Tower A' });
  await page.getByRole('button', { name: 'Start tracking' }).last().click();
  const rec = backend.table('compliance_records').find((r) => r.requirement_id === backend.find('compliance_requirements', { name: 'Chemical storage inspection' }).id);
  expect(rec).toMatchObject({ site_id: ID.siteTowerA, status: 'pending', due_date: dateOffset(30) });
  await expect(page.getByRole('row', { name: /Chemical storage inspection/ })).toContainText('Harbour Point – Tower A');
});

test('a manager verifies a record that someone else is responsible for', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/compliance');
  const row = page.getByRole('row', { name: /COIDA letter of good standing/ });
  await expect(row).toContainText('pending');
  await row.getByRole('button', { name: 'Approve' }).click();

  await expect(row).toContainText('compliant');
  expect(backend.find('compliance_records', { id: ID.recordCoida })).toMatchObject({ status: 'compliant', verified_by: PERSONAS.operations_manager.profileId });
  expect(backend.find('compliance_records', { id: ID.recordCoida }).completed_date).not.toBeNull();
});

test('a responsible person cannot verify their own compliance record', async ({ page, app }) => {
  const backend = await app.open('supervisor');
  await page.goto('/compliance');
  await page.getByRole('row', { name: /COIDA letter of good standing/ }).getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('compliance_records', { id: ID.recordCoida }).status).toBe('pending');
});

test('rejecting a record marks it non-compliant', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/compliance');
  await page.getByRole('row', { name: /COIDA letter of good standing/ }).getByRole('button', { name: 'Reject' }).click();
  await expect(page.getByRole('row', { name: /COIDA/ })).toContainText('non compliant');
  expect(backend.find('compliance_records', { id: ID.recordCoida }).status).toBe('non_compliant');
});

test('employees cannot open Compliance', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/compliance');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('a failure loading compliance data is shown rather than an empty register', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  backend.fault('compliance_records', { method: 'GET', status: 500, message: 'database unavailable' });
  await page.goto('/compliance');
  await expect(page.getByRole('alert')).toHaveText('Failed to load compliance data.');
});
