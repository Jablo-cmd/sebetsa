import { test, expect, type Page } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { fulfillJson } from './utils/mockAuth';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { installSebetsaMocks, buildProfileRow, buildEmployeeRow } from './utils/sebetsaData';

/**
 * A practical accessibility baseline, not a full audit: automated scanning
 * (axe-core) only catches a subset of WCAG issues — missing labels,
 * contrast, landmark/role misuse, unlabelled form controls — and says
 * nothing about keyboard-flow sensibility or screen-reader phrasing.
 * Failing this means a genuine, tool-detectable defect; passing it is a
 * floor, not a certification. Most feature areas already carry their own
 * "has no serious/critical accessibility violations" test next to their
 * functional tests (see attendance.spec.ts, leave.spec.ts, tasks.spec.ts,
 * reports.spec.ts, dashboard.spec.ts, etc.) — this file only covers the
 * pages that don't belong to any single feature module: the unauthenticated
 * login screen, the plain self-service dashboard variant, and the
 * employees directory table.
 */
async function expectNoSeriousViolations(page: Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) {
    console.log(JSON.stringify(serious, null, 2));
  }
  expect(serious, `${serious.length} serious/critical accessibility violation(s) found — see console output above for detail`).toEqual([]);
}

test('Login page has no serious/critical accessibility violations', async ({ page }) => {
  await page.goto('/login');
  await expect(page.getByRole('heading', { name: 'Sign in to your account' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('the plain self-service dashboard has no serious/critical accessibility violations', async ({ page }) => {
  // dashboard.spec.ts already covers the management-role variant with the
  // operational-exceptions panel — this covers the simpler workspace
  // dashboard an employee (or any role without reports.view) sees instead.
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /^Welcome/ })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Employees directory has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'hr_user' }) });
  await page.route('**/rest/v1/departments*', async (route) => {
    if (route.request().method() !== 'GET') return route.fallback();
    await fulfillJson(route, []);
  });
  await page.route('**/rest/v1/employees*', async (route) => {
    const url = new URL(route.request().url());
    if (route.request().method() !== 'GET' || !url.searchParams.has('limit')) return route.fallback();
    await fulfillJson(route, [buildEmployeeRow({ first_name: 'Karabo', last_name: 'Mokoena' })]);
  });

  await page.goto('/employees');
  await expect(page.getByRole('heading', { name: 'Employees' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
