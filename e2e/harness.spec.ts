import { test, expect } from './utils/test';
import { KNOWN_TABLES } from './utils/fakeBackend';

/**
 * Proves the E2E harness fails loudly instead of silently passing: an
 * unmodelled table, an unregistered RPC and an off-origin request are each
 * recorded (and then cleared here so the strict fixture does not fail this
 * very test). If any of these stopped being recorded, every other spec could
 * produce false positives.
 */

test('unmodelled tables, unregistered RPCs and off-origin requests are all caught', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/dashboard');
  await expect(page.getByRole('heading', { name: /Welcome/ })).toBeVisible();

  const results = await page.evaluate(async () => {
    const supabase = 'http://localhost:54321';
    const a = await fetch(`${supabase}/rest/v1/learners?select=*`);
    const b = await fetch(`${supabase}/rest/v1/rpc/definitely_not_a_function`, { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } });
    const c = await fetch(`${supabase}/functions/v1/payments-initiate`, { method: 'POST' });
    const d = await fetch('https://example.com/exfiltrate').then((r) => r.status).catch(() => 'blocked');
    return { table: a.status, rpc: b.status, other: c.status, offOrigin: d };
  });

  expect(results).toEqual({ table: 501, rpc: 501, other: 501, offOrigin: 'blocked' });
  expect(backend.unmocked).toEqual([
    'GET /rest/v1/learners (table not modelled)',
    'RPC definitely_not_a_function (no handler registered)',
    'POST /functions/v1/payments-initiate',
  ]);
  expect(app.offOrigin).toHaveLength(1);

  // Clear so the auto strict-network assertion (which would otherwise fail this test) passes.
  backend.unmocked.length = 0;
  app.offOrigin.length = 0;
});

test('the fake backend enforces tenant isolation like RLS', async ({ page, app }) => {
  const backend = await app.open('operations_manager');
  await page.goto('/dashboard');

  const outcome = await page.evaluate(async () => {
    const headers = { 'content-type': 'application/json', prefer: 'return=representation' };
    const read = await fetch('http://localhost:54321/rest/v1/sites?select=*').then((r) => r.json());
    const write = await fetch('http://localhost:54321/rest/v1/sites', {
      method: 'POST',
      headers,
      body: JSON.stringify({ tenant_id: '00000000-0000-4000-8000-000100000002', client_id: '00000000-0000-4000-8000-000300000090', name: 'Smuggled site' }),
    });
    return { names: (read as { name: string }[]).map((s) => s.name), writeStatus: write.status };
  });

  expect(outcome.names).not.toContain('Rival Site');
  expect(outcome.names).toHaveLength(3);
  expect(outcome.writeStatus).toBe(403);
  expect(backend.table('sites').some((s) => s.name === 'Smuggled site')).toBe(false);
});

test('every table the app queries is modelled by the backend', () => {
  expect(KNOWN_TABLES.length).toBeGreaterThan(50);
  expect(new Set(KNOWN_TABLES).size).toBe(KNOWN_TABLES.length);
});
