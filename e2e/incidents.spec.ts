import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import {
  installSebetsaMocks,
  buildProfileRow,
  buildEmployeeRow,
  buildIncidentRow,
  buildIncidentActionRow,
} from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

/** Genuine Sebetsa Phase N — Compliance, Safety & Incident Management E2E
 * coverage. Real UI, mocked REST/RPC — database-internal RLS/lifecycle
 * assertions live in supabase/rls-tests/compliance_incidents.sql. */

test('employee can report an incident', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'employee' }),
    employee: buildEmployeeRow(),
    incidents: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'report_incident') {
        const created = buildIncidentRow({ description: payload.p_description, category: payload.p_category, severity: payload.p_severity });
        state.incidents = [created];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(created) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/incidents');
  await expect(page.getByRole('heading', { name: 'Incidents' })).toBeVisible();
  await expect(page.getByText('No incidents reported.')).toBeVisible();

  await page.getByLabel('Description').fill('Slip near the loading bay');
  await page.getByRole('button', { name: 'Report' }).click();

  await expect(page.getByText('INC-2026-000001')).toBeVisible();
});

test('operations_manager can progress an incident through its lifecycle and manage corrective actions', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });
  const state = await installSebetsaMocks(page, {
    profile: buildProfileRow({ role: 'operations_manager' }),
    incidents: [buildIncidentRow({ status: 'reported' })],
    incidentActions: [],
    onRpc: async (fnName, payload, route) => {
      if (fnName === 'transition_incident_status') {
        const updated = { ...(state.incidents?.[0] ?? buildIncidentRow()), status: payload.p_new_status };
        state.incidents = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      if (fnName === 'add_incident_action') {
        const created = buildIncidentActionRow({ description: payload.p_description });
        state.incidentActions = [created];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(created) });
        return true;
      }
      if (fnName === 'complete_incident_action') {
        const updated = { ...(state.incidentActions?.[0] ?? buildIncidentActionRow()), status: 'completed' };
        state.incidentActions = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      if (fnName === 'verify_incident_action') {
        const updated = { ...(state.incidentActions?.[0] ?? buildIncidentActionRow()), status: 'verified' };
        state.incidentActions = [updated];
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(updated) });
        return true;
      }
      return false;
    },
  });

  await page.goto('/incidents');
  await page.getByRole('button', { name: /INC-2026-000001/ }).click();
  await expect(page.getByRole('heading', { name: 'Incident INC-2026-000001' })).toBeVisible();

  await page.getByRole('button', { name: 'Move to Acknowledged' }).click();
  await expect(page.getByText('Status: Acknowledged')).toBeVisible();

  await page.getByLabel('New action').fill('Place wet floor signage');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByText('Place wet floor signage')).toBeVisible();

  await page.getByRole('button', { name: 'Complete' }).click();
  await page.getByRole('button', { name: 'Verify' }).click();
});

test('an employee is blocked from Compliance', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }) });

  await page.goto('/compliance');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('Incidents has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });
  await installSebetsaMocks(page, { profile: buildProfileRow({ role: 'employee' }), incidents: [buildIncidentRow()] });
  await page.goto('/incidents');
  await expect(page.getByRole('heading', { name: 'Incidents' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
