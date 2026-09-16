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

const CLIENT_ID = 'client-1';
const SURVEY_ID = 'survey-1';

/** Sebetsa Phase S — Site Survey E2E coverage. Real UI, mocked REST/RPC —
 * database-internal RLS/conversion assertions live in
 * supabase/rls-tests/site_surveys.sql. */

test('operations_manager can fill in a site survey, mark it completed, and convert it to a real site', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });

  let surveyRow: Record<string, unknown> = {
    id: SURVEY_ID,
    tenant_id: SEBETSA_TENANT_ID,
    client_id: CLIENT_ID,
    site_id: null,
    conducted_by: null,
    status: 'draft',
    prospective_site_name: 'ABC Corporate Park',
    address: '1 Main Road',
    building_type: null,
    floor_count: null,
    approx_area_sqm: null,
    office_count: null,
    bathroom_count: null,
    kitchen_count: null,
    entrance_count: null,
    common_area_count: null,
    window_count: null,
    floor_types: null,
    special_surfaces: null,
    operating_hours: null,
    access_restrictions: null,
    required_services: null,
    equipment_requirements: null,
    consumable_requirements: null,
    risks: null,
    special_instructions: null,
    notes: null,
    conducted_at: '2026-01-01T00:00:00Z',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };
  let convertedSite: Record<string, unknown> | null = null;

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const method = route.request().method();

    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'operations_manager' }));
    if (path.endsWith('/clients')) return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    if (path.endsWith('/site_surveys')) {
      if (method === 'PATCH') {
        const payload = JSON.parse(route.request().postData() ?? '{}');
        surveyRow = { ...surveyRow, ...payload };
        return fulfillJson(route, surveyRow);
      }
      return fulfillJson(route, surveyRow);
    }
    if (path.includes('/rpc/convert_site_survey_to_site')) {
      convertedSite = {
        id: 'site-from-survey-1',
        tenant_id: SEBETSA_TENANT_ID,
        client_id: CLIENT_ID,
        region_id: null,
        name: 'ABC Corporate Park',
        address: '1 Main Road',
        site_type: null,
        status: 'onboarding',
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z',
      };
      surveyRow = { ...surveyRow, site_id: convertedSite.id, status: 'converted' };
      return fulfillJson(route, convertedSite);
    }
    if (path.endsWith('/sites')) return fulfillJson(route, convertedSite ?? {});

    if (method === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/site-surveys/${SURVEY_ID}`);
  await expect(page.getByRole('heading', { name: 'ABC Corporate Park' })).toBeVisible();

  await page.getByLabel('Bathrooms').fill('4');
  await page.getByLabel('Offices').fill('20');
  await page.getByRole('button', { name: 'Save survey' }).click();

  await page.getByRole('button', { name: 'Mark completed' }).click();
  await expect(page.getByText('completed', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Convert to site' }).click();
  await expect(page).toHaveURL(/\/sites\/site-from-survey-1$/);
});

test('an employee is blocked from Site Surveys', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'employee' }));
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/site-surveys');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('Site Surveys has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'organization_administrator' }));
    if (path.endsWith('/clients')) return fulfillJson(route, [{ id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' }]);
    if (path.endsWith('/site_surveys')) return fulfillJson(route, []);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/site-surveys');
  await expect(page.getByRole('heading', { name: 'Site Surveys' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Site survey detail page has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'organization_administrator' }));
    if (path.endsWith('/clients')) return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    if (path.endsWith('/site_surveys')) {
      return fulfillJson(route, { id: SURVEY_ID, tenant_id: SEBETSA_TENANT_ID, client_id: CLIENT_ID, site_id: null, conducted_by: null, status: 'draft', prospective_site_name: 'ABC Corporate Park', address: null, building_type: null, floor_count: null, approx_area_sqm: null, office_count: null, bathroom_count: null, kitchen_count: null, entrance_count: null, common_area_count: null, window_count: null, floor_types: null, special_surfaces: null, operating_hours: null, access_restrictions: null, required_services: null, equipment_requirements: null, consumable_requirements: null, risks: null, special_instructions: null, notes: null, conducted_at: '2026-01-01T00:00:00Z', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    }
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/site-surveys/${SURVEY_ID}`);
  await expect(page.getByRole('heading', { name: 'ABC Corporate Park' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
