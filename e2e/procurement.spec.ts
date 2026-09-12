import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildProcurementRequestRow } from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

test('employee can submit a procurement request', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    procurementRequests: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'submit_procurement_request') {
        const created = buildProcurementRequestRow({ item_description: payload.p_item_description, quantity: payload.p_quantity, status: 'submitted' });
        state.procurementRequests = [created];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(created) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/procurement');
  await expect(page.getByRole('heading', { name: 'Procurement' })).toBeVisible();

  await page.getByLabel('Description').fill('Replacement mop heads');
  await page.getByLabel('Quantity').fill('10');
  await page.getByRole('button', { name: 'Submit' }).click();

  await expect(page.getByText('Replacement mop heads × 10')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Approve' })).toHaveCount(0);
});

test('operations_manager can approve and advance a procurement request through to completion', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    procurementRequests: [buildProcurementRequestRow({ status: 'submitted' })],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'decide_procurement_request') {
        const updated = { ...(state.procurementRequests?.[0] ?? buildProcurementRequestRow()), status: payload.p_approve ? 'approved' : 'rejected' };
        state.procurementRequests = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      if (fnName === 'advance_procurement_request') {
        const updated = { ...(state.procurementRequests?.[0] ?? buildProcurementRequestRow()), status: payload.p_new_status };
        state.procurementRequests = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/procurement');
  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByText('Approved', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Mark Ordered' }).click();
  await expect(page.getByText('Ordered', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Mark Received' }).click();
  await expect(page.getByText('Received', { exact: true })).toBeVisible();
});

test('Procurement has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), procurementRequests: [buildProcurementRequestRow()] });
  await page.goto('/procurement');
  await expect(page.getByRole('heading', { name: 'Procurement' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
