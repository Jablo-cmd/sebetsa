import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { SEBETSA_TENANT_ID, buildOrganizationRow, buildProfileRow, fulfillJson } from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

const METRICS_ROW = {
  active_employee_count: 12,
  attendance_rate_pct: 92.5,
  late_attendance_count: 3,
  pending_leave_requests: 2,
  approved_leave_days: 15,
  task_completion_rate_pct: 88.2,
  overdue_task_count: 4,
  open_incident_count: 1,
  critical_incident_count: 0,
  active_asset_count: 20,
  assets_in_maintenance_count: 2,
  active_contract_count: 5,
  contracts_expiring_count: 1,
  qualifications_expiring_count: 3,
  trainings_completed_count: 7,
};

/** Genuine Sebetsa Phase R — Analytics, Reporting & Management
 * Intelligence E2E coverage. Real UI, mocked RPC — database-internal
 * security (the SECURITY-INVOKER role/tenant scoping proof) lives in
 * supabase/rls-tests/analytics_reporting.sql. */

test('organization_administrator sees real operational metrics and can export them', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'organization_administrator' }));
    if (path.includes('/rpc/get_operational_metrics')) return fulfillJson(route, [METRICS_ROW]);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/reports');
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible();
  await expect(page.getByText('12', { exact: true })).toBeVisible();
  await expect(page.getByText('92.5%')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Export CSV' })).toBeVisible();
});

test('site_manager sees Reports but no export action (view-only, no reports.export)', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'site_manager' }));
    if (path.includes('/rpc/get_operational_metrics')) return fulfillJson(route, [{ ...METRICS_ROW, active_employee_count: 4 }]);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/reports');
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible();
  await expect(page.getByText('4', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Export CSV' })).toHaveCount(0);
});

test('an employee is blocked from Reports', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'employee' }));
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/reports');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('Reports has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow({ tenant_id: SEBETSA_TENANT_ID }));
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'hr_user' }));
    if (path.includes('/rpc/get_operational_metrics')) return fulfillJson(route, [METRICS_ROW]);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/reports');
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
