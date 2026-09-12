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
  critical_incident_count: 1,
  active_asset_count: 20,
  assets_in_maintenance_count: 2,
  active_contract_count: 5,
  contracts_expiring_count: 1,
  qualifications_expiring_count: 3,
  trainings_completed_count: 7,
};

/** The dashboard's operational-exceptions row (see
 * OperationalExceptionsPanel) — introduced in the UI/UX transformation
 * pass, reusing Phase R's get_operational_metrics() RPC. Only a role
 * holding reports.view gets this row; an employee keeps the simpler
 * workspace view. */

test('operations_manager sees real operational exceptions on their dashboard', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow({ tenant_id: SEBETSA_TENANT_ID }));
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'operations_manager' }));
    if (path.includes('/rpc/get_operational_metrics')) return fulfillJson(route, [METRICS_ROW]);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/dashboard');
  await expect(page.getByText(/Welcome/)).toBeVisible();
  await expect(page.getByText('Open incidents')).toBeVisible();
  await expect(page.getByText('1 critical')).toBeVisible();
  await expect(page.getByText('Overdue tasks')).toBeVisible();
});

test('an employee sees the simpler workspace dashboard, not tenant-wide exceptions', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'employee' }));
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/dashboard');
  await expect(page.getByText(/Welcome/)).toBeVisible();
  await expect(page.getByText('Open incidents')).toHaveCount(0);
  await expect(page.getByText('Your Workspace', { exact: true })).toBeVisible();
});

test('Dashboard has no serious/critical accessibility violations for a management role', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'hr_user' }));
    if (path.includes('/rpc/get_operational_metrics')) return fulfillJson(route, [METRICS_ROW]);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/dashboard');
  await expect(page.getByText(/Welcome/)).toBeVisible();
  await expectNoSeriousViolations(page);
});
