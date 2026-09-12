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

test('operations_manager can define a compliance requirement, start tracking it, and verify the record', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const requirements: Record<string, unknown>[] = [];
  let records: Record<string, unknown>[] = [];

  await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'upsert_compliance_record') {
        const created = {
          id: 'record-1',
          tenant_id: 'tenant-1',
          requirement_id: payload.p_requirement_id,
          due_date: payload.p_due_date,
          status: 'pending',
        };
        records = [created];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(created) });
        return true;
      }
      if (fnName === 'verify_compliance_record') {
        const updated = { ...(records[0] ?? {}), status: payload.p_approve ? 'compliant' : 'non_compliant' };
        records = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      return false;
    },
  });

  await page.route('**/rest/v1/compliance_requirements*', async (route) => {
    if (route.request().method() === 'POST') {
      const payload = JSON.parse(route.request().postData() ?? '{}');
      const created = { id: 'req-1', tenant_id: 'tenant-1', is_active: true, ...payload };
      requirements.push(created);
      return fulfillJson(route, created);
    }
    return fulfillJson(route, requirements);
  });

  await page.route('**/rest/v1/compliance_records*', async (route) => {
    if (route.request().method() === 'GET') return fulfillJson(route, records);
    return route.fallback();
  });

  await page.goto('/compliance');
  await expect(page.getByRole('heading', { name: 'Compliance' })).toBeVisible();

  await page.getByLabel('Name').fill('Fire Safety Certificate');
  await page.getByLabel('Category').fill('safety');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('Fire Safety Certificate')).toBeVisible();

  await page.getByRole('button', { name: 'Start tracking' }).click();
  await expect(page.getByText('pending')).toBeVisible();

  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByText('compliant')).toBeVisible();
});

test('an employee is blocked from Compliance', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/compliance');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('Compliance has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'operations_manager' }) });
  await page.goto('/compliance');
  await expect(page.getByRole('heading', { name: 'Compliance' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
