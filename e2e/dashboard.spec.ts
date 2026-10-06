import { test, expect, expectNoSeriousViolations } from './utils/test';

const METRICS = {
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

const panel = (page: import('@playwright/test').Page, label: string) => page.getByRole('link', { name: new RegExp(label) });

test('a manager sees operational exceptions with their real figures', async ({ page, app }) => {
  await app.open('operations_manager', { rpc: { get_operational_metrics: () => [METRICS] } });
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome, Omar/ })).toBeVisible();
  await expect(panel(page, 'Open incidents')).toContainText('1');
  await expect(panel(page, 'Open incidents')).toContainText('1 critical');
  await expect(panel(page, 'Overdue tasks')).toContainText('4');
  await expect(panel(page, 'Pending leave')).toContainText('2');
  await expect(panel(page, 'Contracts expiring')).toContainText('1');
  await expect(panel(page, 'Certifications expiring')).toContainText('3');
  await expect(page.getByText('Your Workspace', { exact: true })).toHaveCount(0);
});

test('each exception links to the page where it is handled', async ({ page, app }) => {
  await app.open('operations_manager', { rpc: { get_operational_metrics: () => [METRICS] } });
  const targets: [string, RegExp][] = [
    ['Open incidents', /\/incidents$/],
    ['Overdue tasks', /\/tasks\/management$/],
    ['Pending leave', /\/leave\/management$/],
    ['Contracts expiring', /\/contracts$/],
    ['Certifications expiring', /\/development\/manage$/],
  ];
  for (const [label, url] of targets) {
    await page.goto('/dashboard');
    await panel(page, label).click();
    await expect(page).toHaveURL(url);
  }
});

test('with nothing critical the incident caption says so', async ({ page, app }) => {
  await app.open('hr_user', { rpc: { get_operational_metrics: () => [{ ...METRICS, critical_incident_count: 0 }] } });
  await page.goto('/dashboard');
  await expect(panel(page, 'Open incidents')).toContainText('None critical');
  await expectNoSeriousViolations(page);
});

test('an employee sees their own workspace, not tenant-wide exceptions', async ({ page, app }) => {
  const backend = await app.open('employee');
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome, Thabo/ })).toBeVisible();
  await expect(page.getByText('Your Workspace', { exact: true })).toBeVisible();
  await expect(page.getByText('Open incidents')).toHaveCount(0);
  expect(backend.requests.filter((r) => r.rpc === 'get_operational_metrics')).toEqual([]);
});

test('a failing metrics call says the figures are unavailable instead of hiding the panel', async ({ page, app }) => {
  await app.open('operations_manager', { rpc: { get_operational_metrics: (_a, ctx) => ctx.fail('boom', 'XX000', 500) } });
  await page.goto('/dashboard');
  await expect(page.getByRole('status').filter({ hasText: 'Operational figures are unavailable' })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
});

test('the dashboard is usable for every internal role and carries no serious accessibility violations', async ({ page, app }) => {
  for (const role of ['organization_administrator', 'regional_manager', 'site_manager', 'supervisor', 'client_user'] as const) {
    await app.open(role, { rpc: { get_operational_metrics: () => [METRICS] } });
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();
    await expectNoSeriousViolations(page);
  }
});
