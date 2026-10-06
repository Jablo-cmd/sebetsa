import { test, expect } from './utils/test';
import { ID, PERSONAS, TODAY, dateOffset } from './utils/sebetsaFixtures';

const LERATO_REQUEST = '00000000-0000-4000-8000-003100000001';
const THABO_BALANCE = '00000000-0000-4000-8000-003000000001';
const LERATO_BALANCE = '00000000-0000-4000-8000-003000000002';

async function openRequestForm(page: import('@playwright/test').Page) {
  await page.goto('/leave');
  await page.getByRole('button', { name: 'Request leave' }).click();
  return page.getByRole('dialog');
}

test('My Leave shows the employee\'s own balance and requests only', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/leave');
  await expect(page.getByRole('heading', { name: 'My Leave' })).toBeVisible();
  await expect(page.getByText('13', { exact: true })).toBeVisible(); // 15 opening - 2 used
  await expect(page.getByText('days remaining', { exact: false })).toBeVisible();
  await expect(page.getByText("You haven't requested any leave yet.")).toBeVisible();
  await expect(page.getByText('Lerato')).toHaveCount(0);
});

test('employee submits leave, the pending days are reserved, and cancelling releases them', async ({ page, app }) => {
  const backend = await app.open('employee');
  const dialog = await openRequestForm(page);
  await dialog.getByLabel('Leave type').selectOption({ label: 'Annual' });
  await dialog.getByLabel('Start date').fill(dateOffset(14));
  await dialog.getByLabel('End date').fill(dateOffset(16));
  await dialog.getByLabel('Reason').fill('Family wedding');
  await expect(dialog.getByText(/3 calendar day\(s\)/)).toBeVisible();
  await dialog.getByRole('button', { name: 'Submit request' }).click();

  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByRole('row', { name: /Annual/ })).toContainText('Pending');
  await expect(page.getByText(/3 pending/)).toBeVisible();
  const request = backend.find('leave_requests', { employee_id: PERSONAS.employee.employeeId });
  expect(request).toMatchObject({ status: 'pending', start_date: dateOffset(14), end_date: dateOffset(16), reason: 'Family wedding', decided_by: null });
  expect(backend.find('leave_balances', { id: THABO_BALANCE })).toMatchObject({ pending: 3, remaining: 10 });

  await page.getByRole('button', { name: 'Cancel' }).click();
  await expect(page.getByRole('row', { name: /Annual/ })).toContainText('Cancelled');
  expect(backend.find('leave_balances', { id: THABO_BALANCE })).toMatchObject({ pending: 0, remaining: 13 });
  expect(backend.find('leave_requests', { id: request.id }).cancelled_by).toBe(PERSONAS.employee.profileId);
});

test('the request form validates dates and half-day rules without sending anything', async ({ page, app }) => {
  const backend = await app.open('employee');
  const dialog = await openRequestForm(page);
  await dialog.getByRole('button', { name: 'Submit request' }).click();
  await expect(dialog.getByText('Leave type is required')).toBeVisible();
  await expect(dialog.getByText('Start date is required')).toBeVisible();

  await dialog.getByLabel('Leave type').selectOption({ label: 'Annual' });
  await dialog.getByLabel('Start date').fill(dateOffset(10));
  await dialog.getByLabel('End date').fill(dateOffset(8));
  await dialog.getByRole('button', { name: 'Submit request' }).click();
  await expect(dialog.getByText('End date must not be before start date')).toBeVisible();

  await dialog.getByLabel('End date').fill(dateOffset(11));
  await dialog.getByLabel('Half day').check();
  await dialog.getByRole('button', { name: 'Submit request' }).click();
  await expect(dialog.getByText('A half-day request must have the same start and end date')).toBeVisible();
  expect(backend.requests.filter((r) => r.rpc === 'submit_leave_request')).toEqual([]);
});

test('a leave type that needs documentation is refused without it, and accepted with it', async ({ page, app }) => {
  const backend = await app.open('employee');
  const dialog = await openRequestForm(page);
  await dialog.getByLabel('Leave type').selectOption({ label: 'Sick' });
  await dialog.getByLabel('Start date').fill(dateOffset(1));
  await dialog.getByLabel('End date').fill(dateOffset(1));
  await dialog.getByRole('button', { name: 'Submit request' }).click();

  await expect(dialog.getByRole('alert')).toHaveText('Supporting documentation is required for this leave type.');
  expect(backend.table('leave_requests').filter((r) => r.employee_id === PERSONAS.employee.employeeId)).toHaveLength(0);

  await dialog.getByLabel('Supporting document reference').fill('MED-2026-0042');
  await dialog.getByRole('button', { name: 'Submit request' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('leave_requests', { employee_id: PERSONAS.employee.employeeId }).supporting_document_ref).toBe('MED-2026-0042');
});

test('the approval queue shows WHO is asking, and approving updates the balance and records the decision', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/leave/management');
  await expect(page.getByRole('heading', { name: 'Leave Management' })).toBeVisible();
  const row = page.getByRole('row', { name: /Lerato Mahlangu/ });
  await expect(row).toContainText('Annual');
  await expect(row).toContainText('Family visit');

  await row.getByRole('button', { name: 'Review' }).click();
  const dialog = page.getByRole('dialog', { name: 'Review leave request' });
  await expect(dialog.getByText('Lerato Mahlangu')).toBeVisible();
  await dialog.getByLabel('Notes').fill('Enjoy');
  await dialog.getByRole('button', { name: 'Approve' }).click();

  await expect(page.getByText('No leave requests in this status.')).toBeVisible();
  expect(backend.find('leave_requests', { id: LERATO_REQUEST })).toMatchObject({ status: 'approved', decided_by: PERSONAS.operations_manager.profileId, decision_notes: 'Enjoy' });
  expect(backend.find('leave_balances', { id: LERATO_BALANCE })).toMatchObject({ pending: 0, used: 3, remaining: 12 });
  expect(backend.table('audit_log').some((a) => a.action === 'leave_approved' && a.entity_id === LERATO_REQUEST)).toBe(true);
});

test('rejecting releases the pending days; an approved request can later be revoked and the days return', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/leave/management');
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Review' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Reject' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('leave_requests', { id: LERATO_REQUEST }).status).toBe('rejected');
  expect(backend.find('leave_balances', { id: LERATO_BALANCE })).toMatchObject({ pending: 0, used: 0, remaining: 15 });

  // Put it back to pending (as if resubmitted), then approve and revoke it.
  backend.find('leave_requests', { id: LERATO_REQUEST }).status = 'pending';
  Object.assign(backend.find('leave_balances', { id: LERATO_BALANCE }), { pending: 3, remaining: 12 });
  await page.reload();
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Review' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('leave_balances', { id: LERATO_BALANCE })).toMatchObject({ used: 3, remaining: 12 });

  await page.getByRole('button', { name: 'Approved' }).click();
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Review' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Revoke' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('leave_requests', { id: LERATO_REQUEST }).status).toBe('revoked');
  expect(backend.find('leave_balances', { id: LERATO_BALANCE })).toMatchObject({ used: 0, remaining: 15 });
});

test('approval warns when the leave overlaps shifts that are already scheduled', async ({ page, app }) => {
  await app.open('operations_manager', {
    customize: (t) => {
      const r = t.leave_requests.find((x) => x.id === LERATO_REQUEST);
      if (r) Object.assign(r, { start_date: TODAY, end_date: dateOffset(1) });
    },
  });
  await page.goto('/leave/management');
  await page.getByRole('row', { name: /Lerato Mahlangu/ }).getByRole('button', { name: 'Review' }).click();
  await expect(page.getByText('1 scheduled shift(s) overlap this leave range.')).toBeVisible();
  await expect(page.getByText('approving here does not change any shift')).toBeVisible();
});

test('a manager cannot decide their own leave request (separation of duties); someone else can', async ({ page, app, browser }) => {
  void browser;
  const olivia = PERSONAS.organization_administrator;
  const ownRequest = '00000000-0000-4000-8000-003100000050';
  const seed = (t: Record<string, Record<string, unknown>[]>) =>
    t.leave_requests.push({ id: ownRequest, tenant_id: ID.org, employee_id: olivia.employeeId, leave_type_id: ID.leaveAnnual, start_date: dateOffset(30), end_date: dateOffset(31), is_half_day: false, half_day_period: null, reason: 'Own break', status: 'pending', decided_by: null, decided_at: null, decision_notes: null, supporting_document_ref: null, cancelled_at: null, cancelled_by: null, created_at: '2026-09-01T00:00:00Z', updated_at: '2026-09-01T00:00:00Z' });

  const backend = await app.open('organization_administrator', { customize: seed });
  await page.goto('/leave/management');
  await page.getByRole('row', { name: /Olivia Okafor/ }).getByRole('button', { name: 'Review' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toContainText('cannot approve, verify or close a record you raised');
  expect(backend.find('leave_requests', { id: ownRequest }).status).toBe('pending');

  // A different approver (operations manager) can decide it.
  backend.session = { ...backend.session, userId: PERSONAS.operations_manager.profileId, role: 'operations_manager', email: PERSONAS.operations_manager.email };
  await page.getByRole('dialog').getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  expect(backend.find('leave_requests', { id: ownRequest }).status).toBe('approved');
});

test('Team Leave shows who is away but never the reason or decision notes', async ({ page, app }) => {
  await app.open('site_manager');
  await page.goto('/leave/team');
  await expect(page.getByRole('heading', { name: 'Team Leave' })).toBeVisible();
  await expect(page.getByRole('row', { name: /Lerato Mahlangu/ })).toBeVisible();
  await expect(page.getByRole('columnheader', { name: 'Reason' })).toHaveCount(0);
  await expect(page.getByText('Family visit')).toHaveCount(0);
  await expect(page.getByRole('button', { name: /Review|Approve|Reject/ })).toHaveCount(0);
});

test('employees cannot open the approval queue or leave configuration', async ({ page, app }) => {
  await app.open('employee');
  for (const path of ['/leave/management', '/leave/configuration']) {
    await page.goto(path);
    await expect(page, path).toHaveURL('http://localhost:5173/dashboard');
  }
});

test('hr_user adds a leave type and takes it out of use', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/leave/configuration');
  await page.getByLabel('New leave type name').fill('Study leave');
  await page.getByRole('button', { name: /Add|Create/ }).first().click();

  const row = page.getByRole('row', { name: /Study leave/ });
  await expect(row).toBeVisible();
  expect(backend.find('leave_types', { name: 'Study leave' }).tenant_id).toBe(ID.org);

  await row.getByRole('button', { name: /Deactivate/ }).click();
  await expect(row).toContainText(/inactive/i);
  expect(backend.find('leave_types', { name: 'Study leave' }).status).toBe('inactive');
});

test('hr_user adjusts a balance through the ledger RPC, with a visible result', async ({ page, app }) => {
  const backend = await app.open('hr_user');
  await page.goto('/leave/configuration');
  await page.getByLabel('Employee').fill('Thabo');
  await page.getByRole('button', { name: 'Thabo Nkosi' }).click();
  await page.locator('#adjust-leave-type').selectOption({ label: 'Annual' });
  await page.getByLabel('Adjustment amount (days, may be negative)').fill('2');
  await page.getByLabel('Note').fill('Carry-over correction');
  await page.getByRole('button', { name: 'Apply adjustment' }).click();

  await expect(page.getByText('Balance updated — remaining now 15 day(s).')).toBeVisible();
  expect(backend.find('leave_balances', { id: THABO_BALANCE }).adjustment).toBe(2);
  expect(backend.requests.some((r) => r.method === 'PATCH' && r.table === 'leave_balances')).toBe(false);
});
