// Sebetsa health endpoint.
//   GET  (no secret)            -> { status: 'ok' | 'degraded' }, HTTP 200 / 503. Nothing else is disclosed.
//   GET  x-health-secret: <OPS_HEALTH_SECRET> -> adds the alert list and the counts behind it.
// Used by .github/workflows/uptime.yml and by any external monitor. Fails closed: a database error is 'degraded'.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { evaluateAlerts, type OpsHealth, overallStatus, secretMatches } from './logic.ts';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const healthSecret = Deno.env.get('OPS_HEALTH_SECRET') ?? '';

function respond(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'GET') return respond({ error: 'method_not_allowed' }, 405);
  const detailed = await secretMatches(req.headers.get('x-health-secret'), healthSecret);

  try {
    const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    const { data, error } = await supabase.rpc('ops_health');
    if (error) throw error;
    const alerts = evaluateAlerts(data as OpsHealth);
    const status = overallStatus(alerts);
    console.log(JSON.stringify({ event: 'health_check', status, alerts: alerts.map((a) => a.key) }));
    return respond(detailed ? { status, alerts, health: data } : { status }, status === 'ok' ? 200 : 503);
  } catch (e) {
    // Counts only; never echo the error to an unauthenticated caller.
    console.error(JSON.stringify({ event: 'health_check_failed', message: e instanceof Error ? e.message : 'unknown' }));
    return respond(detailed ? { status: 'degraded', error: 'database_unreachable' } : { status: 'degraded' }, 503);
  }
});
