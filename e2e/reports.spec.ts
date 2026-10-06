import { readFileSync } from 'node:fs';
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
  critical_incident_count: 0,
  active_asset_count: 20,
  assets_in_maintenance_count: 2,
  active_contract_count: 5,
  contracts_expiring_count: 1,
  qualifications_expiring_count: 3,
  trainings_completed_count: 7,
};

const fixedMetrics = { get_operational_metrics: () => [METRICS] };

/** The card whose label is `label` (cards are plain divs: label, value, hint). */
const card = (page: import('@playwright/test').Page, label: string) =>
  page.getByText(label, { exact: true }).locator('xpath=..');

test('operational metrics are shown for the current month with their detail lines', async ({ page, app }) => {
  const backend = await app.open('organization_administrator', { rpc: fixedMetrics });
  await page.goto('/reports');
  await expect(page.getByRole('heading', { name: 'Reports' })).toBeVisible();
  await expect(page.getByText('Operational metrics for 2026-09-01 to 2026-09-30')).toBeVisible();

  await expect(card(page, 'Active employees')).toContainText('12');
  await expect(card(page, 'Attendance rate')).toContainText('92.5%');
  await expect(card(page, 'Attendance rate')).toContainText('3 late records');
  await expect(card(page, 'Task completion rate')).toContainText('88.2%');
  await expect(card(page, 'Task completion rate')).toContainText('4 overdue');
  await expect(card(page, 'Open incidents')).toContainText('0 critical');
  await expect(card(page, 'Active assets')).toContainText('2 in maintenance');
  await expect(card(page, 'Active contracts')).toContainText('1 expiring within 30 days');
  await expect(card(page, 'Certifications expiring soon')).toContainText('3');
  await expect(card(page, 'Trainings completed (period)')).toContainText('7');

  const call = backend.requests.find((r) => r.rpc === 'get_operational_metrics');
  expect(call?.body).toMatchObject({ p_period_start: '2026-09-01', p_period_end: '2026-09-30' });
  await expectNoSeriousViolations(page);
});

test('the default metrics are derived from the seeded workforce data', async ({ page, app }) => {
  await app.open('operations_manager');
  await page.goto('/reports');
  // Fixture: 2 open tasks of 3 (1 completed) → 33.3%, one open incident, one active contract per client.
  await expect(card(page, 'Task completion rate')).toContainText('33.3%');
  await expect(card(page, 'Pending leave requests')).toContainText('1');
  await expect(card(page, 'Open incidents')).toContainText('1');
});

test('an administrator exports the metrics as a CSV that matches what is on screen', async ({ page, app }) => {
  await app.open('organization_administrator', { rpc: fixedMetrics });
  await page.goto('/reports');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export CSV' }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe('sebetsa-operational-metrics-2026-09-01-to-2026-09-30.csv');
  const lines = readFileSync(await download.path(), 'utf8').split('\r\n');
  expect(lines[0]).toBe('Metric,Value,Detail');
  expect(lines).toContain('Active employees,12,');
  expect(lines).toContain('Attendance rate,92.5%,3 late records');
  expect(lines).toContain('Active contracts,5,1 expiring within 30 days');
  expect(lines).toHaveLength(11);
});

test('roles without reports.export see the figures but no export action', async ({ page, app }) => {
  for (const role of ['site_manager', 'supervisor', 'regional_manager'] as const) {
    await app.open(role, { rpc: { get_operational_metrics: () => [{ ...METRICS, active_employee_count: 4 }] } });
    await page.goto('/reports');
    await expect(card(page, 'Active employees')).toContainText('4');
    await expect(page.getByRole('button', { name: 'Export CSV' })).toHaveCount(0);
  }
});

test('HR can view and export reports', async ({ page, app }) => {
  await app.open('hr_user', { rpc: fixedMetrics });
  await page.goto('/reports');
  await expect(page.getByRole('button', { name: 'Export CSV' })).toBeVisible();
});

test('a metrics failure is reported instead of an empty or stale page', async ({ page, app }) => {
  await app.open('organization_administrator', {
    rpc: { get_operational_metrics: (_a, ctx) => ctx.fail('permission denied for function get_operational_metrics', '42501', 403) },
  });
  await page.goto('/reports');
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page.getByText('No metrics available.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Export CSV' })).toHaveCount(0);
});

test('employees and clients cannot open Reports', async ({ page, app }) => {
  for (const role of ['employee', 'client_user'] as const) {
    await app.open(role);
    await page.goto('/reports');
    await expect(page).not.toHaveURL(/reports/);
  }
});
