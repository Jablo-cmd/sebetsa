import { test, expect, expectNoSeriousViolations } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

const PDF = (name: string, bytes = 64) => ({ name, mimeType: 'application/pdf', buffer: Buffer.alloc(bytes, 'x') });
const SLA_EXISTING = '00000000-0000-4000-8000-003700000001';

test('the contract page shows its terms, client, covered sites and existing SLA metric', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await expect(page.getByRole('heading', { name: 'HP-2026-001' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Harbour Point Offices' })).toHaveAttribute('href', `/clients/${ID.clientHarbour}`);
  await expect(page.getByText('2026-01-01', { exact: true })).toBeVisible();
  await expect(page.getByText('2026-12-31', { exact: true })).toBeVisible();
  await expect(page.getByLabel('Contract status')).toHaveValue('active');
  await expect(page.getByRole('link', { name: /Harbour Point – Tower A/ })).toBeVisible();
  await expect(page.getByText('Daily task completion ≥ 95%')).toBeVisible();
  await expect(page.getByText(/Task completion rate \(%\) — target ≥ 95/)).toBeVisible();
  await expect(page.getByText('No documents uploaded for this contract yet.')).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('computing an SLA measures the real month: 1 of 3 tasks completed misses a 95% target', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await page.getByRole('button', { name: 'Compute this month' }).click();
  await expect(page.getByText('Latest: 33.33 (target missed) — 2026-09-01 to 2026-09-30')).toBeVisible();
  expect(backend.find('sla_measurements', { sla_definition_id: SLA_EXISTING })).toMatchObject({
    measured_value: 33.33,
    target_met: false,
    computed_by: PERSONAS.operations_manager.profileId,
    period_start: '2026-09-01',
    period_end: '2026-09-30',
  });
});

test('a manager defines a new metric and a lower target is met by the same data', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  const add = page.getByRole('button', { name: 'Add SLA metric' });
  await expect(add).toBeDisabled();
  await page.getByLabel('Metric name').fill('Basic completion');
  await page.getByLabel('Target').fill('30');
  await add.click();
  await expect(page.getByText('Basic completion', { exact: true })).toBeVisible();
  expect(backend.find('sla_definitions', { name: 'Basic completion' })).toMatchObject({
    contract_id: ID.contractHarbour,
    site_id: ID.siteTowerA,
    metric_type: 'task_completion_rate',
    target_value: 30,
    threshold_operator: 'gte',
  });
  const card = page.locator('div.rounded-xl', { hasText: 'Basic completion' });
  await card.getByRole('button', { name: 'Compute this month' }).click();
  await expect(card.getByText(/Latest: 33.33 \(target met\)/)).toBeVisible();
  // The original 95% target on the same data is still reported as missed once computed.
  await page.locator('div.rounded-xl', { hasText: 'Daily task completion' }).getByRole('button', { name: 'Compute this month' }).click();
  await expect(page.getByText(/Latest: 33.33 \(target missed\)/)).toBeVisible();
});

test('response-time metrics use a "no more than" threshold', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await page.getByLabel('Metric name').fill('Incident response');
  await page.getByLabel('Metric type').selectOption('incident_response_hours');
  await page.getByLabel('Target').fill('4');
  await page.getByRole('button', { name: 'Add SLA metric' }).click();
  await expect(page.getByText(/Incident response time \(hrs\) — target ≤ 4/)).toBeVisible();
  expect(backend.find('sla_definitions', { name: 'Incident response' })).toMatchObject({ threshold_operator: 'lte', target_value: 4 });
  // No closed incidents in the period → 0 hours, which satisfies "≤ 4".
  const card = page.locator('div.rounded-xl', { hasText: 'Incident response' });
  await card.getByRole('button', { name: 'Compute this month' }).click();
  await expect(card.getByText(/Latest: 0 \(target met\)/)).toBeVisible();
});

test('a contract with no linked site cannot take an SLA metric', async ({ page, app }) => {
  await app.open('operations_manager', { customize: (t) => (t.contract_sites = t.contract_sites.filter((l) => l.contract_id !== ID.contractHarbour)) });
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await expect(page.getByText('No sites linked to this contract yet.')).toBeVisible();
  await page.getByLabel('Metric name').fill('Anything');
  await expect(page.getByRole('button', { name: 'Add SLA metric' })).toBeDisabled();
});

test('SLA failures are shown, and a later success clears them', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  backend.fault('sla_definitions', { method: 'POST', times: 1 });
  await page.getByLabel('Metric name').fill('Will fail');
  await page.getByRole('button', { name: 'Add SLA metric' }).click();
  await expect(page.getByText('Failed to create the SLA definition.')).toBeVisible();
  expect(backend.table('sla_definitions')).toHaveLength(1);

  await page.getByRole('button', { name: 'Add SLA metric' }).click();
  await expect(page.getByText('Will fail', { exact: true })).toBeVisible();
  await expect(page.getByText('Failed to create the SLA definition.')).toHaveCount(0);
});

test('the compute RPC refusing a caller is reported', async ({ page, app }) => {
  await app.open('operations_manager', { rpc: { compute_sla_measurement: (_a, ctx) => ctx.fail('insufficient_privilege: cannot compute SLA measurements for this tenant', '42501', 403) } });
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await page.getByRole('button', { name: 'Compute this month' }).click();
  await expect(page.getByText("You don't have permission to do this.")).toBeVisible();
});

test('changing the contract status persists; a failure is shown and the old status is restored', async ({ page, app }) => {
  const backend = await app.open('organization_administrator');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await page.getByLabel('Contract status').selectOption('suspended');
  await expect(page.getByLabel('Contract status')).toHaveValue('suspended');
  expect(backend.find('contracts', { id: ID.contractHarbour }).status).toBe('suspended');

  backend.fault('contracts', { method: 'PATCH', times: 1 });
  await page.getByLabel('Contract status').selectOption('terminated');
  await expect(page.getByText('Failed to update contract status.')).toBeVisible();
  await expect(page.getByLabel('Contract status')).toHaveValue('suspended');
  expect(backend.find('contracts', { id: ID.contractHarbour }).status).toBe('suspended');
});

test('edit details: validation, saving new terms and replacing the covered sites', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractNorthgate}`);
  await expect(page.getByRole('heading', { name: 'NG-2026-002' })).toBeVisible();
  await expect(page.getByRole('link', { name: /Main Atrium/ })).toBeVisible();
  await expect(page.getByRole('link', { name: /Food Court/ })).toBeVisible();

  await page.getByRole('button', { name: 'Edit details' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('Contract number').fill('');
  await dialog.getByLabel('End date').fill('2026-01-01');
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog.getByText('Contract number is required')).toBeVisible();
  await expect(dialog.getByText('End date must be on or after the start date')).toBeVisible();

  await dialog.getByLabel('Contract number').fill('NG-2026-002R');
  await dialog.getByLabel('End date').fill('2027-02-28');
  await dialog.getByLabel('SLA notes').fill('Weekend cover added');
  await dialog.getByRole('checkbox', { name: /Food Court/ }).uncheck();
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);

  await expect(page.getByRole('heading', { name: 'NG-2026-002R' })).toBeVisible();
  await expect(page.getByText('Weekend cover added')).toBeVisible();
  await expect(page.getByRole('link', { name: /Food Court/ })).toHaveCount(0);
  expect(backend.find('contracts', { id: ID.contractNorthgate })).toMatchObject({ contract_number: 'NG-2026-002R', end_date: '2027-02-28' });
  expect(backend.table('contract_sites').filter((l) => l.contract_id === ID.contractNorthgate).map((l) => l.site_id)).toEqual([ID.siteAtrium]);
});

test('a refused site change leaves the contract\'s existing sites in place', async ({ page, app }) => {
  const backend = await app.open('operations_manager', {
    rpc: { set_contract_sites: (_a, ctx) => ctx.fail('invalid_reference: site does not belong to the contract\'s client', '22023', 400) },
  });
  await page.goto(`/contracts/${ID.contractNorthgate}`);
  await page.getByRole('button', { name: 'Edit details' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('checkbox', { name: /Food Court/ }).uncheck();
  await dialog.getByRole('button', { name: 'Save' }).click();
  await expect(dialog.getByRole('alert')).toContainText('does not belong to the chosen client');
  expect(backend.table('contract_sites').filter((l) => l.contract_id === ID.contractNorthgate)).toHaveLength(2);
});

test('uploading contract documents versions them, and a failed upload leaves no phantom record', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  const input = page.getByLabel(/Upload a document/);

  await input.setInputFiles(PDF('signed-agreement.pdf'));
  await expect(page.getByText('signed-agreement.pdf')).toBeVisible();
  await expect(page.getByText('v1')).toBeVisible();
  expect(backend.uploads).toHaveLength(1);
  expect(backend.uploads[0]).toMatchObject({ bucket: 'contract-documents' });
  expect(backend.uploads[0].path.startsWith(`${ID.org}/${ID.contractHarbour}/`)).toBe(true);

  await input.setInputFiles(PDF('addendum.pdf'));
  await expect(page.getByText('addendum.pdf')).toBeVisible();
  await expect(page.getByText('v2')).toBeVisible();

  backend.failUploads = 1;
  await input.setInputFiles(PDF('lost.pdf'));
  await expect(page.getByText('Failed to upload the document.')).toBeVisible();
  await expect(page.getByText('lost.pdf')).toHaveCount(0);
  expect(backend.table('contract_documents').map((d) => d.file_name).sort()).toEqual(['addendum.pdf', 'signed-agreement.pdf']);
  expect(backend.requests.filter((r) => r.rpc === 'cancel_contract_document_upload')).toHaveLength(1);
});

test('the server refuses a disallowed file type and nothing is stored', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await page.getByLabel(/Upload a document/).setInputFiles({ name: 'macro.exe', mimeType: 'application/x-msdownload', buffer: Buffer.alloc(10) });
  await expect(page.getByText('That file type is not allowed.')).toBeVisible();
  expect(backend.uploads).toEqual([]);
  expect(backend.table('contract_documents')).toHaveLength(0);
});

test('opening a contract document uses a short-lived signed URL', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await page.getByLabel(/Upload a document/).setInputFiles(PDF('signed-agreement.pdf'));
  await expect(page.getByText('signed-agreement.pdf')).toBeVisible();
  const popupPromise = page.waitForEvent('popup');
  await page.getByRole('button', { name: 'Open signed-agreement.pdf' }).click();
  const popup = await popupPromise;
  // The signed-URL response is a file; don't wait for a document load, only for the navigation target.
  await expect.poll(() => popup.url()).toContain('/storage/v1/object/sign/contract-documents/');
  expect(popup.url()).toContain('token=');
});

test('roles that cannot manage org structure get a read-only contract page', async ({ page, app }) => {
  for (const role of ['site_manager', 'regional_manager'] as const) {
    await app.open(role);
    await page.goto(`/contracts/${ID.contractHarbour}`);
    await expect(page.getByRole('heading', { name: 'HP-2026-001' })).toBeVisible();
    await expect(page.getByLabel('Contract status')).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Edit details' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Add SLA metric' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Compute this month' })).toHaveCount(0);
    await expect(page.getByLabel(/Upload a document/)).toHaveCount(0);
  }
});

test('an unknown or other-tenant contract is "not found", never someone else\'s data', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/contracts/00000000-0000-4000-8000-00ee00000001');
  await expect(page.getByText('Contract not found')).toBeVisible();
  await expect(page.getByRole('link', { name: 'Back to Contracts' })).toBeVisible();
});

test('a failed contract load shows an error, not an empty page', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  backend.fault('contracts', { method: 'GET' });
  await page.goto(`/contracts/${ID.contractHarbour}`);
  await expect(page.getByText('Something went wrong')).toBeVisible();
});

test('employees, clients, HR and supervisors cannot open contracts', async ({ page, app }) => {
  for (const role of ['employee', 'client_user', 'hr_user', 'supervisor'] as const) {
    await app.open(role);
    await page.goto(`/contracts/${ID.contractHarbour}`);
    await expect(page).not.toHaveURL(/contracts/);
  }
});
