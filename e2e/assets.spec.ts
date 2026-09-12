import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildAssetRow, buildInventoryItemRow, fulfillJson } from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/** Genuine Sebetsa Phase O — Procurement, Inventory & Asset Management E2E
 * coverage. Real UI, mocked REST/RPC — database-internal RLS/lifecycle
 * assertions live in supabase/rls-tests/procurement_inventory_assets.sql. */

test('operations_manager can register an asset and send it to maintenance', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    assets: [],
  });

  await page.route('**/rest/v1/assets*', async (route) => {
    if (route.request().method() === 'POST') {
      const payload = JSON.parse(route.request().postData() ?? '{}');
      const created = buildAssetRow({ id: 'asset-1', asset_number: payload.asset_number, name: payload.name, category: payload.category });
      state.assets = [created];
      return fulfillJson(route, created);
    }
    return route.fallback();
  });

  await page.route('**/rest/v1/rpc/transition_asset_status', async (route) => {
    const payload = JSON.parse(route.request().postData() ?? '{}');
    const updated = { ...(state.assets?.[0] ?? buildAssetRow()), status: payload.p_new_status };
    state.assets = [updated];
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
  });

  await page.goto('/assets');
  await expect(page.getByRole('heading', { name: 'Assets' })).toBeVisible();

  await page.getByLabel('Asset number').fill('AST-001');
  await page.getByLabel('Name').fill('Floor Buffer');
  await page.getByLabel('Category').fill('equipment');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('AST-001 — Floor Buffer')).toBeVisible();

  await page.getByRole('button', { name: 'Send to maintenance' }).click();
  await expect(page.getByText('Maintenance', { exact: true })).toBeVisible();
});

test('an employee is blocked from Assets', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/assets');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('operations_manager can add an inventory item and record a receipt', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    inventoryItems: [],
  });

  await page.route('**/rest/v1/sites*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, [{ id: 'site-1', name: 'Site One' }]);
  });

  await page.route('**/rest/v1/inventory_items*', async (route) => {
    if (route.request().method() === 'POST') {
      const payload = JSON.parse(route.request().postData() ?? '{}');
      const created = buildInventoryItemRow({ id: 'item-1', sku: payload.sku, name: payload.name, category: payload.category });
      state.inventoryItems = [created];
      return fulfillJson(route, created);
    }
    return route.fallback();
  });

  let balance = 0;
  await page.route('**/rest/v1/rpc/get_inventory_balance', async (route) => {
    await fulfillJson(route, balance);
  });
  await page.route('**/rest/v1/rpc/record_inventory_movement', async (route) => {
    const payload = JSON.parse(route.request().postData() ?? '{}');
    balance += payload.p_movement_type === 'receipt' ? payload.p_quantity : -payload.p_quantity;
    await fulfillJson(route, { id: 'movement-1' });
  });

  await page.goto('/inventory');
  await expect(page.getByRole('heading', { name: 'Inventory' })).toBeVisible();

  await page.getByLabel('SKU').fill('SKU-001');
  await page.getByLabel('Name').fill('Disinfectant 5L');
  await page.getByLabel('Category').fill('consumables');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('SKU-001 — Disinfectant 5L')).toBeVisible();

  await page.getByLabel('Quantity for Disinfectant 5L').fill('20');
  await page.getByRole('button', { name: 'Receive' }).click();
  await expect(page.getByText('20 each')).toBeVisible();
});

test('Assets has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'operations_manager' }), assets: [buildAssetRow()] });
  await page.goto('/assets');
  await expect(page.getByRole('heading', { name: 'Assets' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
