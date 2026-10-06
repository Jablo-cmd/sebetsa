import { test, expect } from './utils/test';
import { ID, PERSONAS } from './utils/sebetsaFixtures';

const row = (page: import('@playwright/test').Page, name: RegExp) => page.getByRole('row', { name });

test('stock levels are shown per site, and low stock is flagged against the reorder level', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/inventory');
  await expect(page.getByRole('heading', { name: 'Inventory' })).toBeVisible();
  await page.locator('#inventory-site').selectOption(ID.siteTowerA);

  await expect(row(page, /Multi-surface cleaner/)).toContainText('24 each');
  await expect(row(page, /Multi-surface cleaner/)).not.toContainText('Low stock'); // reorder at 10
  await expect(row(page, /Mop heads/)).toContainText('8 each');
  await expect(row(page, /Mop heads/)).toContainText('Low stock'); // reorder at 20
});

test('switching site shows that site\'s own balances, not the first site\'s', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/inventory');
  await page.locator('#inventory-site').selectOption(ID.siteTowerA);
  await expect(row(page, /Multi-surface cleaner/)).toContainText('24 each');

  await page.locator('#inventory-site').selectOption(ID.siteAtrium);
  await expect(row(page, /Multi-surface cleaner/)).toContainText('0 each');
  await expect(row(page, /Multi-surface cleaner/)).toContainText('Low stock');
});

test('receiving and issuing stock is recorded against the selected site', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/inventory');
  await page.locator('#inventory-site').selectOption(ID.siteAtrium);

  await page.getByLabel('Quantity for Mop heads').fill('30');
  await row(page, /Mop heads/).getByRole('button', { name: 'Receive' }).click();
  await expect(row(page, /Mop heads/)).toContainText('30 each');
  expect(backend.table('inventory_movements').find((m) => m.item_id === ID.itemMopHeads && m.site_id === ID.siteAtrium)).toMatchObject({ movement_type: 'receipt', quantity: 30, performed_by: PERSONAS.operations_manager.profileId });

  await page.getByLabel('Quantity for Mop heads').fill('12');
  await row(page, /Mop heads/).getByRole('button', { name: 'Issue' }).click();
  await expect(row(page, /Mop heads/)).toContainText('18 each');
  // The other site's stock is untouched.
  expect(backend.table('inventory_movements').filter((m) => m.site_id === ID.siteTowerA)).toHaveLength(2);
});

test('issuing more than is in stock is refused and the balance does not change', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/inventory');
  await page.locator('#inventory-site').selectOption(ID.siteTowerA);
  await page.getByLabel('Quantity for Mop heads').fill('50');
  await row(page, /Mop heads/).getByRole('button', { name: 'Issue' }).click();

  await expect(page.getByRole('alert')).toHaveText('There is not enough stock for this movement.');
  await expect(row(page, /Mop heads/)).toContainText('8 each');
  expect(backend.table('inventory_movements').filter((m) => m.item_id === ID.itemMopHeads)).toHaveLength(1);
});

test('a zero or empty quantity is rejected before any request', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/inventory');
  await page.getByLabel('Quantity for Mop heads').fill('0');
  await row(page, /Mop heads/).getByRole('button', { name: 'Receive' }).click();
  await expect(page.getByRole('alert')).toHaveText('Enter a quantity greater than zero.');
  expect(backend.requests.filter((r) => r.rpc === 'record_inventory_movement')).toEqual([]);
});

test('a manager adds an item with a reorder level and it is flagged straight away', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/inventory');
  await page.getByLabel('SKU').fill('CHEM-099');
  await page.getByLabel('Name').fill('Glass cleaner 750ml');
  await page.getByLabel('Category').fill('consumables');
  await page.getByLabel('Reorder level').fill('6');
  await page.getByRole('button', { name: 'Add' }).click();

  await expect(row(page, /Glass cleaner/)).toContainText('Low stock'); // 0 <= 6
  expect(backend.find('inventory_items', { sku: 'CHEM-099' })).toMatchObject({ tenant_id: ID.org, reorder_threshold: 6, unit: 'each' });
});

test('employees cannot open inventory', async ({ page, app }) => {
  await app.open('employee');
  await page.goto('/inventory');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});
