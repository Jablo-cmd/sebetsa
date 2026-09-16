import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { seedSebetsaSession } from './utils/sebetsaAuth';
import { SEBETSA_TENANT_ID, buildOrganizationRow, buildProfileRow, buildContractRow, fulfillJson } from './utils/sebetsaData';

async function expectNoSeriousViolations(page: import('@playwright/test').Page) {
  const results = await new AxeBuilder({ page }).analyze();
  const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical');
  if (serious.length > 0) console.log(JSON.stringify(serious, null, 2));
  expect(serious, `${serious.length} serious/critical accessibility violation(s) — see console output`).toEqual([]);
}

const CONTRACT_ID = 'contract-1';
const CLIENT_ID = 'client-1';
const SITE_ID = 'site-1';

/** Genuine Sebetsa Phase P — Client, Contract & SLA Management E2E
 * coverage, focused on the new SLA/document sections added to the existing
 * (pre-Phase-P, previously untested) ContractDetailPage. Real UI, mocked
 * REST/RPC — database-internal RLS/lifecycle assertions live in
 * supabase/rls-tests/client_contract_sla.sql. */

test('operations_manager can define an SLA metric, compute it, and see the real result', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });

  let slaDefinitions: Record<string, unknown>[] = [];
  let slaMeasurements: Record<string, unknown>[] = [];

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const method = route.request().method();

    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'operations_manager' }));
    if (path.endsWith('/contracts')) {
      return fulfillJson(route, buildContractRow());
    }
    if (path.endsWith('/clients')) {
      if (url.searchParams.get('limit')) return fulfillJson(route, [{ id: CLIENT_ID, name: 'Client One' }]);
      return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    }
    if (path.endsWith('/contract_sites')) return fulfillJson(route, [{ site_id: SITE_ID }]);
    if (path.endsWith('/sites')) return fulfillJson(route, [{ id: SITE_ID, tenant_id: SEBETSA_TENANT_ID, client_id: CLIENT_ID, name: 'Site One', status: 'active' }]);
    if (path.endsWith('/site_areas')) return fulfillJson(route, []);
    if (path.endsWith('/scope_of_work_items')) return fulfillJson(route, []);
    if (path.endsWith('/contract_versions')) return fulfillJson(route, []);
    if (path.endsWith('/sla_definitions')) {
      if (method === 'POST') {
        const payload = JSON.parse(route.request().postData() ?? '{}');
        const created = { id: 'sla-1', tenant_id: SEBETSA_TENANT_ID, contract_id: CONTRACT_ID, site_id: SITE_ID, name: payload.name, metric_type: payload.metric_type, target_value: payload.target_value, threshold_operator: payload.threshold_operator, measurement_period: 'monthly', is_active: true };
        slaDefinitions = [created];
        return fulfillJson(route, created);
      }
      return fulfillJson(route, slaDefinitions);
    }
    if (path.endsWith('/sla_measurements')) return fulfillJson(route, slaMeasurements);
    if (path.endsWith('/contract_documents')) return fulfillJson(route, []);

    if (path.includes('/rpc/compute_sla_measurement')) {
      const measurement = { id: 'measurement-1', tenant_id: SEBETSA_TENANT_ID, sla_definition_id: slaDefinitions[0]?.id, period_start: '2026-09-01', period_end: '2026-09-30', measured_value: 75, target_met: false, computed_at: new Date().toISOString() };
      slaMeasurements = [measurement];
      return fulfillJson(route, measurement);
    }

    if (method === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/contracts/${CONTRACT_ID}`);
  await expect(page.getByRole('heading', { name: 'CTR-001' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'SLA performance' })).toBeVisible();

  await page.getByLabel('Metric name').fill('Task completion');
  await page.getByRole('button', { name: 'Add SLA metric' }).click();
  await expect(page.getByText('Task completion', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Compute this month' }).click();
  await expect(page.getByText(/Latest: 75 \(target missed\)/)).toBeVisible();
});

test('Contract detail page has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'organization_administrator' }));
    if (path.endsWith('/contracts')) {
      return fulfillJson(route, buildContractRow());
    }
    if (path.endsWith('/clients')) return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/contracts/${CONTRACT_ID}`);
  await expect(page.getByRole('heading', { name: 'CTR-001' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('operations_manager can edit commercial terms and see the change recorded in version history', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });

  let contractRow = buildContractRow();
  const versions: Record<string, unknown>[] = [];

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const method = route.request().method();

    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'operations_manager' }));
    if (path.endsWith('/contracts')) {
      if (method === 'PATCH') {
        const payload = JSON.parse(route.request().postData() ?? '{}');
        contractRow = { ...contractRow, ...payload };
        versions.unshift({
          id: `version-${versions.length + 1}`,
          tenant_id: SEBETSA_TENANT_ID,
          contract_id: CONTRACT_ID,
          version_number: versions.length + 1,
          snapshot: {},
          change_summary: 'contract value: null -> 150000',
          changed_by: null,
          effective_date: '2026-09-16',
          created_at: new Date().toISOString(),
        });
        return fulfillJson(route, contractRow);
      }
      return fulfillJson(route, contractRow);
    }
    if (path.endsWith('/clients')) return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    if (path.endsWith('/contract_sites')) return fulfillJson(route, [{ site_id: SITE_ID }]);
    if (path.endsWith('/sites')) return fulfillJson(route, [{ id: SITE_ID, tenant_id: SEBETSA_TENANT_ID, client_id: CLIENT_ID, name: 'Site One', status: 'active' }]);
    if (path.endsWith('/site_areas')) return fulfillJson(route, []);
    if (path.endsWith('/scope_of_work_items')) return fulfillJson(route, []);
    if (path.endsWith('/contract_versions')) return fulfillJson(route, versions);
    if (path.endsWith('/contract_documents')) return fulfillJson(route, []);
    if (path.endsWith('/sla_definitions')) return fulfillJson(route, []);

    if (method === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/contracts/${CONTRACT_ID}`);
  await expect(page.getByRole('heading', { name: 'CTR-001' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Commercial terms' })).toBeVisible();

  await page.getByRole('button', { name: 'Edit', exact: true }).click();
  await page.getByLabel('Contract value (ZAR)').fill('150000');
  await page.getByRole('button', { name: 'Save terms' }).click();

  await expect(page.getByRole('heading', { name: 'Version history' })).toBeVisible();
  await expect(page.getByText(/contract value: null -> 150000/)).toBeVisible();
});

test('an employee is blocked from the contract detail page entirely (no org_structure permission)', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'employee' }));
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/contracts/${CONTRACT_ID}`);
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('a site_manager can view commercial terms and scope of work but the Generate task template action requires org_structure.manage', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'site_manager' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'site_manager' }));
    if (path.endsWith('/contracts')) return fulfillJson(route, buildContractRow({ contract_value: 150000 }));
    if (path.endsWith('/clients')) return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    if (path.endsWith('/contract_sites')) return fulfillJson(route, [{ site_id: SITE_ID }]);
    if (path.endsWith('/sites')) return fulfillJson(route, [{ id: SITE_ID, tenant_id: SEBETSA_TENANT_ID, client_id: CLIENT_ID, name: 'Site One', status: 'active' }]);
    if (path.endsWith('/site_areas')) return fulfillJson(route, [{ id: 'area-1', tenant_id: SEBETSA_TENANT_ID, site_id: SITE_ID, name: 'Reception', description: null, sort_order: 0, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' }]);
    if (path.endsWith('/scope_of_work_items')) return fulfillJson(route, [{ id: 'scope-1', tenant_id: SEBETSA_TENANT_ID, contract_id: CONTRACT_ID, site_area_id: 'area-1', task_name: 'Vacuum carpet', frequency: 'daily', estimated_minutes: 15, assigned_role: null, required_equipment: null, required_consumables: null, ppe_notes: null, instructions: null, requires_evidence: false, priority: 'normal', status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' }]);
    if (path.endsWith('/contract_versions')) return fulfillJson(route, []);
    if (path.endsWith('/contract_documents')) return fulfillJson(route, []);
    if (path.endsWith('/sla_definitions')) return fulfillJson(route, []);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/contracts/${CONTRACT_ID}`);
  await expect(page.getByRole('heading', { name: 'CTR-001' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Commercial terms' })).toBeVisible();
  await expect(page.getByText(/R\s*150[,.]?000/)).toBeVisible();
  await expect(page.getByRole('button', { name: 'Edit', exact: true })).not.toBeVisible();
  await expect(page.getByText('Vacuum carpet')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Generate task template' })).not.toBeVisible();
});
