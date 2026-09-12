import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildProfileRow,
  buildEmployeeRow,
  buildEmployeeSkillRow,
  buildPerformanceReviewRow,
  fulfillJson,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/** Genuine Sebetsa Phase Q — Workforce Performance, Training & Skills E2E
 * coverage. Real UI, mocked REST/RPC — database-internal RLS/lifecycle
 * assertions (including the finalisation lock and the reviewee-only
 * acknowledgement rule) live in
 * supabase/rls-tests/workforce_performance_training_skills.sql. */

test('employee sees their own skills and can acknowledge a performance review', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    employeeSkills: [buildEmployeeSkillRow()],
    performanceReviews: [buildPerformanceReviewRow({ status: 'employee_review' })],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'advance_performance_review') {
        const updated = { ...(state.performanceReviews?.[0] ?? buildPerformanceReviewRow()), status: payload.p_new_status, employee_comments: payload.p_employee_comments };
        state.performanceReviews = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      return false;
    },
  });

  await page.route('**/rest/v1/skills*', async (route) => fulfillJson(route, []));

  await page.goto('/development');
  await expect(page.getByRole('heading', { name: 'My Development' })).toBeVisible();
  await expect(page.getByText('intermediate (unverified)')).toBeVisible();

  await page.getByRole('button', { name: 'Acknowledge' }).click();
  await expect(page.getByText('Awaiting acknowledgement')).toBeVisible();
});

test('an employee is blocked from Workforce Development management', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/development/manage');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('hr_user can search an employee, verify a skill, and see it as verified', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'hr_user' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'hr_user' }),
    employeeSkills: [buildEmployeeSkillRow()],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'verify_employee_skill') {
        const updated = { ...(state.employeeSkills?.[0] ?? buildEmployeeSkillRow()), verified_by: 'hr-1', verified_at: new Date().toISOString() };
        state.employeeSkills = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      return false;
    },
  });

  await page.route('**/rest/v1/skills*', async (route) => fulfillJson(route, [{ id: 'skill-1', tenant_id: 'tenant-1', name: 'First Aid', category: 'safety' }]));
  await page.route('**/rest/v1/training_programs*', async (route) => fulfillJson(route, []));
  await page.route('**/rest/v1/employees*', async (route) => {
    const url = new URL(route.request().url());
    if (route.request().method() !== 'GET' || !url.searchParams.has('limit')) return route.fallback();
    await fulfillJson(route, [{ id: 'employee-1', first_name: 'Karabo', last_name: 'Mokoena' }]);
  });

  await page.goto('/development/manage');
  await expect(page.getByRole('heading', { name: 'Workforce Development' })).toBeVisible();

  await page.getByLabel('Employee').fill('Karabo');
  await page.getByRole('button', { name: 'Karabo Mokoena' }).click();

  await expect(page.getByText('First Aid — intermediate')).toBeVisible();
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByText('First Aid — intermediate (verified)')).toBeVisible();
});

test('My Development has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow() });
  await page.goto('/development');
  await expect(page.getByRole('heading', { name: 'My Development' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
