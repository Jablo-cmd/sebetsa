import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildProfileRow,
  buildEmployeeRow,
  buildTaskRow,
  buildTaskChecklistItemRow,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

test('employee can view a task, toggle its checklist, add evidence, and complete it', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    tasks: [buildTaskRow()],
    taskChecklistItems: [buildTaskChecklistItemRow()],
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'complete_task') {
        const completed = { ...(state.tasks?.[0] ?? buildTaskRow()), status: 'completed', completed_by: '11111111-1111-1111-1111-111111111111' };
        state.tasks = [completed];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(completed) });
        return true;
      }
      return false;
    },
  });

  await page.route('**/rest/v1/task_checklist_items*', async (route) => {
    if (route.request().method() !== 'PATCH') return route.fallback();
    const updated = { ...buildTaskChecklistItemRow(), is_completed: true, completed_by: '11111111-1111-1111-1111-111111111111' };
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
  });

  await page.goto('/tasks');
  await expect(page.getByRole('heading', { name: 'My Tasks' })).toBeVisible();
  await page.getByText('Inspect fire extinguishers').click();

  await expect(page.getByRole('heading', { name: 'Inspect fire extinguishers' })).toBeVisible();
  const checklistItem = page.getByRole('checkbox', { name: 'Check pressure gauges' });
  await checklistItem.click();
  await expect(checklistItem).toBeChecked();

  await page.getByLabel('Add a note').fill('All extinguishers checked and in date.');
  await page.getByRole('button', { name: 'Add evidence' }).click();

  await page.getByRole('button', { name: 'Mark complete' }).click();
  await expect(page.getByRole('heading', { name: 'Inspect fire extinguishers' })).toHaveCount(0);
});

test('organization_administrator can verify a completed task', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  const completed = buildTaskRow({ status: 'completed' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'organization_administrator' }),
    tasks: [completed],
    onRpc: async (fnName, _payload, route) => {
      if (fnName === 'verify_task') {
        const verified = { ...completed, status: 'verified' };
        state.tasks = [verified];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(verified) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/tasks/management');
  await expect(page.getByRole('heading', { name: 'Task Management' })).toBeVisible();
  await page.getByRole('button', { name: 'Review' }).click();
  await page.getByRole('button', { name: 'Verify' }).click();
  await expect(page.getByRole('heading', { name: 'Inspect fire extinguishers' })).toHaveCount(0);
});

test('an employee is blocked from Task Management', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/tasks/management');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('My Tasks has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), employee: buildEmployeeRow(), tasks: [buildTaskRow()] });
  await page.goto('/tasks');
  await expect(page.getByRole('heading', { name: 'My Tasks' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Task Management has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'organization_administrator' }), tasks: [buildTaskRow()] });
  await page.goto('/tasks/management');
  await expect(page.getByRole('heading', { name: 'Task Management' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
