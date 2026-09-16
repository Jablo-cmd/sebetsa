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
const SITE_ID = 'site-1';
const QUOTE_ID = 'quote-1';

/** Sebetsa Phase R — Quoting & Proposals E2E coverage. Real UI, mocked
 * REST/RPC — database-internal RLS/lifecycle/conversion assertions live in
 * supabase/rls-tests/quotes.sql. */

test('operations_manager can build a quote, recompute totals, approve it, and convert it to a contract', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'operations_manager' });

  let quoteRow: Record<string, unknown> = {
    id: QUOTE_ID,
    tenant_id: SEBETSA_TENANT_ID,
    client_id: CLIENT_ID,
    site_id: SITE_ID,
    quote_number: 'QT-001',
    version: 1,
    status: 'draft',
    expiry_date: null,
    discount_amount: 0,
    tax_rate: 15,
    subtotal: 0,
    tax_amount: 0,
    total_amount: 0,
    notes: null,
    assumptions: null,
    exclusions: null,
    prepared_by: null,
    converted_to_contract_id: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };
  const lineItems: Record<string, unknown>[] = [];
  let contractCreated: Record<string, unknown> | null = null;

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const method = route.request().method();

    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'operations_manager' }));
    if (path.endsWith('/clients')) {
      if (url.searchParams.get('limit') || url.searchParams.get('select')?.includes('id')) {
        return fulfillJson(route, [{ id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' }]);
      }
      return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    }
    if (path.endsWith('/sites')) return fulfillJson(route, [{ id: SITE_ID, tenant_id: SEBETSA_TENANT_ID, client_id: CLIENT_ID, name: 'Site One', status: 'active' }]);
    if (path.endsWith('/quotes')) {
      if (method === 'PATCH') {
        const payload = JSON.parse(route.request().postData() ?? '{}');
        quoteRow = { ...quoteRow, ...payload };
        return fulfillJson(route, quoteRow);
      }
      if (method === 'GET' && url.searchParams.has('id')) return fulfillJson(route, quoteRow);
      return fulfillJson(route, quoteRow);
    }
    if (path.endsWith('/quote_line_items')) {
      if (method === 'POST') {
        const payload = JSON.parse(route.request().postData() ?? '{}');
        const created = {
          id: `line-${lineItems.length + 1}`,
          tenant_id: SEBETSA_TENANT_ID,
          quote_id: QUOTE_ID,
          category: payload.category ?? 'other',
          description: payload.description,
          quantity: payload.quantity,
          unit_rate: payload.unit_rate,
          line_total: payload.quantity * payload.unit_rate,
          sort_order: 0,
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z',
        };
        lineItems.push(created);
        return fulfillJson(route, created);
      }
      return fulfillJson(route, lineItems);
    }
    if (path.includes('/rpc/recompute_quote_totals')) {
      const subtotal = lineItems.reduce((sum, item) => sum + (item.line_total as number), 0);
      const tax = Math.round(subtotal * 0.15 * 100) / 100;
      quoteRow = { ...quoteRow, subtotal, tax_amount: tax, total_amount: subtotal + tax };
      return fulfillJson(route, quoteRow);
    }
    if (path.includes('/rpc/convert_quote_to_contract')) {
      contractCreated = {
        id: 'contract-from-quote-1',
        tenant_id: SEBETSA_TENANT_ID,
        client_id: CLIENT_ID,
        contract_number: 'CTR-FROM-QT-001',
        start_date: '2026-10-01',
        end_date: null,
        status: 'draft',
        responsible_manager_id: null,
        sla_notes: null,
        contract_value: quoteRow.total_amount,
        recurring_value: null,
        billing_frequency: null,
        payment_terms_days: null,
        renewal_date: null,
        auto_renew: false,
        escalation_percentage: null,
        escalation_notes: null,
        service_frequency: null,
        consumables_responsibility: null,
        equipment_responsibility: null,
        labour_notes: null,
        notes: null,
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z',
      };
      quoteRow = { ...quoteRow, converted_to_contract_id: contractCreated.id };
      return fulfillJson(route, contractCreated);
    }
    if (path.endsWith('/contract_sites')) return fulfillJson(route, []);
    if (path.endsWith('/contracts')) return fulfillJson(route, contractCreated ?? {});

    if (method === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/quotes/${QUOTE_ID}`);
  await expect(page.getByRole('heading', { name: 'QT-001' })).toBeVisible();

  await page.getByLabel('Description').fill('Weekly office cleaning');
  await page.getByLabel('Qty').fill('4');
  await page.getByLabel('Unit rate (ZAR)').fill('1000');
  await page.getByRole('button', { name: 'Add line' }).click();

  await expect(page.getByText(/4 × R\s*1[,.]?000\.00 = R\s*4[,.]?000\.00/)).toBeVisible();
  await expect(page.getByText(/R\s*4[,.]?600\.00/)).toBeVisible();

  await page.getByRole('button', { name: 'Mark sent' }).click();
  await expect(page.getByText('sent', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Mark viewed' }).click();
  await page.getByRole('button', { name: 'Mark approved' }).click();

  await expect(page.getByRole('heading', { name: 'Convert to contract' })).toBeVisible();
  await page.getByLabel('Contract number').fill('CTR-FROM-QT-001');
  await page.getByLabel('Start date').fill('2026-10-01');
  await page.getByRole('button', { name: 'Convert to contract' }).click();

  await expect(page).toHaveURL(/\/contracts\/contract-from-quote-1$/);
});

test('an employee is blocked from Quotes', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'employee' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'employee' }));
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/quotes');
  await expect(page).toHaveURL('http://localhost:5173/dashboard');
});

test('Quotes has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'organization_administrator' }));
    if (path.endsWith('/clients')) return fulfillJson(route, [{ id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' }]);
    if (path.endsWith('/quotes')) return fulfillJson(route, []);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto('/quotes');
  await expect(page.getByRole('heading', { name: 'Quotes' })).toBeVisible();
  await expectNoSeriousViolations(page);
});

test('Quote detail page has no serious/critical accessibility violations', async ({ page }) => {
  await seedSebetsaSession(page, { role: 'organization_administrator' });

  await page.route('**/auth/v1/**', async (route) => fulfillJson(route, {}));
  await page.route('**/rest/v1/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/organizations')) return fulfillJson(route, buildOrganizationRow());
    if (path.endsWith('/profiles')) return fulfillJson(route, buildProfileRow({ role: 'organization_administrator' }));
    if (path.endsWith('/clients')) return fulfillJson(route, { id: CLIENT_ID, tenant_id: SEBETSA_TENANT_ID, name: 'Client One', industry: null, primary_contact_name: null, primary_contact_email: null, primary_contact_phone: null, status: 'active', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    if (path.endsWith('/quotes')) {
      return fulfillJson(route, { id: QUOTE_ID, tenant_id: SEBETSA_TENANT_ID, client_id: CLIENT_ID, site_id: SITE_ID, quote_number: 'QT-001', version: 1, status: 'draft', expiry_date: null, discount_amount: 0, tax_rate: 15, subtotal: 0, tax_amount: 0, total_amount: 0, notes: null, assumptions: null, exclusions: null, prepared_by: null, converted_to_contract_id: null, created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z' });
    }
    if (path.endsWith('/quote_line_items')) return fulfillJson(route, []);
    if (route.request().method() === 'GET') return fulfillJson(route, []);
    return fulfillJson(route, {});
  });

  await page.goto(`/quotes/${QUOTE_ID}`);
  await expect(page.getByRole('heading', { name: 'QT-001' })).toBeVisible();
  await expectNoSeriousViolations(page);
});
