import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, fulfillJson } from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

const SITE_ROW = { id: 'site-1', tenant_id: '22222222-2222-2222-2222-222222222222', client_id: 'client-1', name: 'Head Office', address: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' };

test('site operations overview shows staffing counts for the selected site', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'operations_manager' }) });

  await page.route('**/rest/v1/sites*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, [SITE_ROW]);
  });

  let call = 0;
  await page.route('**/rest/v1/site_assignments*', async (route) => {
    call += 1;
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-2/3', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/shifts*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-4/5', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/attendance_records*', async (route) => {
    const url = new URL(route.request().url());
    const status = url.searchParams.get('status') ?? '';
    const total = status.includes('present') ? 2 : status.includes('late') ? 1 : 0;
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': `0-0/${total}`, 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/tasks*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/1', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/site_staffing_requirements*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, [{ id: 'req-1', tenant_id: SITE_ROW.tenant_id, site_id: 'site-1', label: 'Guards', required_count: 4 }]);
  });

  await page.goto('/site-operations');
  await expect(page.getByRole('heading', { name: 'Site Operations' })).toBeVisible();
  await expect(page.getByText('Assigned')).toBeVisible();
  await expect(page.getByText('Required', { exact: true })).toBeVisible();
  void call;
});

test('an employee is blocked from Site Operations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/site-operations');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('Site Operations has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'operations_manager' }) });
  await page.route('**/rest/v1/sites*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, [SITE_ROW]);
  });
  await page.route('**/rest/v1/site_assignments*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/0', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/shifts*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/0', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/attendance_records*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/0', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/tasks*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'content-range': '0-0/0', 'access-control-expose-headers': 'content-range' }, body: '[]' });
  });
  await page.route('**/rest/v1/site_staffing_requirements*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, []);
  });

  await page.goto('/site-operations');
  await expect(page.getByRole('heading', { name: 'Site Operations' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
