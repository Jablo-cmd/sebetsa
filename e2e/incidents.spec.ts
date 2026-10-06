import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

const open = (page: import('@playwright/test').Page, ref: RegExp) => page.getByRole('button', { name: ref }).click();

test('an employee reports an incident against a site; it is stored under their tenant with a reference number', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/incidents');
  await expect(page.getByRole('button', { name: 'Report' })).toBeDisabled();

  await page.getByLabel('Category').selectOption('property_damage');
  await page.getByLabel('Severity').selectOption('high');
  await page.getByLabel('Site').selectOption({ label: 'Northgate Mall – Main Atrium' });
  await page.getByLabel('Description').fill('Glass door cracked by the delivery trolley');
  await page.getByRole('button', { name: 'Report' }).click();

  await expect(page.getByRole('button', { name: /INC-2026-000002/ })).toContainText('Northgate Mall – Main Atrium');
  const created = backend.find('incidents', { reference_number: 'INC-2026-000002' });
  expect(created).toMatchObject({ tenant_id: ID.org, site_id: ID.siteAtrium, category: 'property_damage', severity: 'high', status: 'reported', reported_by: PERSONAS.employee.profileId });
  expect(backend.table('audit_log').some((a) => a.action === 'incident_reported' && a.entity_id === created.id)).toBe(true);
});

test('an employee sees no lifecycle controls on an incident', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByText('Slip near the lobby entrance after mopping.')).toBeVisible();
  await expect(dialog.getByRole('button', { name: /Move to/ })).toHaveCount(0);
  await expect(dialog.getByLabel('New action')).toHaveCount(0);
});

test('a supervisor takes an incident from investigation to closure through corrective actions', async ({ page, app }) => {
  const backend = await app.open('supervisor');
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  const dialog = page.getByRole('dialog', { name: 'Incident INC-2026-000001' });

  // Existing seeded action: complete it, then verify it (someone other than its owner would verify; the owner here is Sarah, so use a new one).
  await dialog.getByLabel('New action').fill('Install anti-slip mats at the lobby entrance');
  await dialog.getByRole('button', { name: 'Add' }).click();
  await expect(dialog.getByText('Install anti-slip mats at the lobby entrance')).toBeVisible();

  await dialog.getByRole('button', { name: 'Move to Corrective action' }).click();
  await expect(dialog.getByText('Status: Corrective action')).toBeVisible();

  const actionRow = (button: string) =>
    dialog
      .locator('div')
      .filter({ hasText: 'Install anti-slip mats at the lobby entrance' })
      .filter({ has: page.getByRole('button', { name: button }) })
      .last();
  await actionRow('Complete').getByRole('button', { name: 'Complete' }).click();
  await expect(dialog.getByText(/^completed/)).toBeVisible();
  await actionRow('Verify').getByRole('button', { name: 'Verify' }).click();
  await expect(dialog.getByText(/^verified/)).toBeVisible();
  const action = backend.find('incident_actions', { description: 'Install anti-slip mats at the lobby entrance' });
  expect(action).toMatchObject({ status: 'verified', verified_by: PERSONAS.supervisor.profileId });

  await dialog.getByRole('button', { name: 'Move to Pending closure' }).click();
  await expect(dialog.getByText('Status: Pending closure')).toBeVisible();
  await dialog.getByRole('button', { name: 'Move to Closed' }).click();
  await expect(dialog.getByText('Status: Closed')).toBeVisible();

  expect(backend.find('incidents', { id: ID.incidentSlip })).toMatchObject({ status: 'closed', closed_by: PERSONAS.supervisor.profileId });
  expect(backend.table('audit_log').filter((a) => a.action === 'incident_status_changed' && a.entity_id === ID.incidentSlip)).toHaveLength(3);
});

test('the person who reported an incident cannot be the one to close it', async ({ page, app }) => {
  const backend = await app.open('supervisor', {
    customize: (t) => {
      const i = t.incidents.find((x) => x.id === ID.incidentSlip);
      if (i) Object.assign(i, { status: 'pending_closure', reported_by: PERSONAS.supervisor.profileId });
    },
  });
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  await page.getByRole('dialog').getByRole('button', { name: 'Move to Closed' }).click();

  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('incidents', { id: ID.incidentSlip }).status).toBe('pending_closure');
});

test('an owner cannot verify their own corrective action', async ({ page, app }) => {
  const backend = await app.open('supervisor', {
    customize: (t) => {
      const a = t.incident_actions.find((x) => x.id === ID.actionSignage);
      if (a) a.status = 'completed'; // owner is Sarah (supervisor)
    },
  });
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  await page.getByRole('dialog').getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('incident_actions', { id: ID.actionSignage }).status).toBe('completed');
});

test('a closed incident can be reopened for investigation', async ({ page, app }) => {
  const backend = await app.open('operations_manager', {
    customize: (t) => {
      const i = t.incidents.find((x) => x.id === ID.incidentSlip);
      if (i) Object.assign(i, { status: 'closed', closed_by: PERSONAS.supervisor.profileId, closed_at: '2026-09-20T10:00:00.000Z' });
    },
  });
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  await page.getByRole('dialog').getByRole('button', { name: 'Reopen for investigation' }).click();
  await expect(page.getByRole('dialog').getByText('Status: Investigating')).toBeVisible();
  expect(backend.find('incidents', { id: ID.incidentSlip })).toMatchObject({ status: 'investigating', closed_by: null });
});

test('an invalid status jump is refused by the server and reported to the user', async ({ page, app }) => {
  const backend = await app.open('supervisor');
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  await page.getByRole('dialog').getByRole('button', { name: 'Move to Corrective action' }).click();
  await expect(page.getByRole('dialog').getByText('Status: Corrective action')).toBeVisible();
  // Another user already advanced it; this stale dialog tries the same step again.
  backend.find('incidents', { id: ID.incidentSlip }).status = 'pending_closure';
  await page.getByRole('dialog').getByRole('button', { name: 'Move to Pending closure' }).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toHaveText('This record cannot move to that status from its current state. Refresh and try again.');
});

test('a failure loading the corrective actions is reported', async ({ page, app }) => {
  const backend = await app.open('supervisor');
  backend.fault('incident_actions', { method: 'GET', status: 500, message: 'database unavailable' });
  await page.goto('/incidents');
  await open(page, /INC-2026-000001/);
  await expect(page.getByRole('dialog').getByRole('alert')).toHaveText('Failed to load the corrective actions.');
});

test('a failed report keeps what was typed and says why', async ({ page, app }) => {
  const backend = await app.open('employee');
  backend.fault('rpc:report_incident', { status: 500, message: 'database unavailable' });
  await page.goto('/incidents');
  await page.getByLabel('Description').fill('Spill in corridor');
  await page.getByRole('button', { name: 'Report' }).click();
  await expect(page.getByText('Failed to report the incident.')).toBeVisible();
  await expect(page.getByLabel('Description')).toHaveValue('Spill in corridor');
});
