import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

test('an employee requests an item for a site with an estimated cost', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/procurement');
  await page.getByLabel('Description').fill('Microfibre cloths (pack of 50)');
  await page.getByLabel('Quantity').fill('4');
  await page.getByLabel('Estimated cost (R)').fill('780');
  await page.getByLabel('Site').selectOption({ label: 'Harbour Point – Tower A' });
  await page.getByRole('button', { name: 'Submit' }).click();

  const entry = page.getByText('Microfibre cloths (pack of 50) × 4');
  await expect(entry).toBeVisible();
  await expect(page.getByText(/Submitted · Harbour Point – Tower A · est\. R780/)).toBeVisible();
  expect(backend.find('procurement_requests', { item_description: 'Microfibre cloths (pack of 50)' })).toMatchObject({ tenant_id: ID.org, requested_by: PERSONAS.employee.profileId, site_id: ID.siteTowerA, status: 'submitted', quantity: 4, estimated_cost: 780 });
});

test('an invalid quantity or cost is rejected before any request', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/procurement');
  await page.getByLabel('Description').fill('Gloves');
  await page.getByLabel('Quantity').fill('-2');
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.getByRole('alert')).toHaveText('Enter a quantity greater than zero.');
  await page.getByLabel('Quantity').fill('2');
  await page.getByLabel('Estimated cost (R)').fill('-5');
  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.getByRole('alert')).toHaveText('The estimated cost must be zero or more.');
  expect(backend.requests.filter((r) => r.rpc === 'submit_procurement_request')).toEqual([]);
});

test('an employee sees requests but has no approval or fulfilment controls', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/procurement');
  await expect(page.getByText('Mop heads x20 × 20')).toBeVisible();
  await expect(page.getByRole('button', { name: /Approve|Reject|Mark/ })).toHaveCount(0);
});

test('a request goes from approval through ordering and receipt to completion, with an audit trail', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/procurement');
  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByText('Approved')).toBeVisible();
  expect(backend.find('procurement_requests', { id: ID.procMops })).toMatchObject({ status: 'approved', approved_by: PERSONAS.operations_manager.profileId });

  await page.getByRole('button', { name: 'Mark Ordered' }).click();
  await expect(page.getByText(/Ordered/)).toBeVisible();
  await page.getByRole('button', { name: 'Mark Received' }).click();
  await expect(page.getByText(/Received/)).toBeVisible();
  await page.getByRole('button', { name: 'Mark Completed' }).click();
  await expect(page.getByText(/Completed/)).toBeVisible();
  await expect(page.getByRole('button', { name: /Approve|Reject|Mark/ })).toHaveCount(0);
  expect(backend.find('procurement_requests', { id: ID.procMops }).status).toBe('completed');
});

test('rejecting needs a reason, which is recorded and shown', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/procurement');
  await expect(page.getByRole('button', { name: 'Reject' })).toBeDisabled();
  await page.getByLabel('Rejection reason for Mop heads x20').fill('Over budget this month');
  await page.getByRole('button', { name: 'Reject' }).click();

  await expect(page.getByText('Reason: Over budget this month')).toBeVisible();
  expect(backend.find('procurement_requests', { id: ID.procMops })).toMatchObject({ status: 'rejected', rejected_reason: 'Over budget this month' });
});

test('a requester cannot approve their own request', async ({ page, app }) => {
  const backend = await app.open('supervisor'); // Sarah raised the seeded request
  await page.goto('/procurement');
  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('alert')).toHaveText("You don't have permission to do this.");
  expect(backend.find('procurement_requests', { id: ID.procMops }).status).toBe('submitted');
});

test('a stale screen cannot skip a step in the workflow', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/procurement');
  await expect(page.getByRole('button', { name: 'Approve' })).toBeVisible();
  backend.find('procurement_requests', { id: ID.procMops }).status = 'cancelled'; // withdrawn elsewhere
  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  expect(backend.find('procurement_requests', { id: ID.procMops }).status).toBe('cancelled');
});
