import { assertEquals } from '@std/assert';
import { evaluateAlerts, type OpsHealth, overallStatus, secretMatches } from './logic.ts';

const healthy = (): OpsHealth => ({
  database: 'ok',
  jobs: [{ job: 'recurring_tasks', last_success_at: new Date().toISOString(), last_status: 'succeeded', failures_since_success: 0 }],
  jobs_never_ran: [],
  notifications: { pending_overdue: 0, oldest_pending_age_seconds: 0, dead_letter: 0, dead_letter_24h: 0, expired_leases: 0 },
  security: { failures_1h: 0, events_24h: 3 },
});

Deno.test('a healthy snapshot raises nothing', () => {
  assertEquals(evaluateAlerts(healthy()), []);
  assertEquals(overallStatus([]), 'ok');
});

Deno.test('repeated job failures are critical', () => {
  const h = healthy();
  h.jobs[0].failures_since_success = 3;
  const a = evaluateAlerts(h);
  assertEquals(a.map((x) => x.key), ['job_failing:recurring_tasks']);
  assertEquals(overallStatus(a), 'degraded');
});

Deno.test('a stale job is only a warning; never-ran jobs are reported', () => {
  const h = healthy();
  h.jobs[0].last_success_at = new Date(Date.now() - 40 * 3600_000).toISOString();
  h.jobs_never_ran = ['audit_retention'];
  const a = evaluateAlerts(h);
  assertEquals(a.map((x) => x.key).sort(), ['job_stale:recurring_tasks', 'jobs_not_scheduled']);
  assertEquals(overallStatus(a), 'ok');
});

Deno.test('notification backlog, dead letters and security failures are critical', () => {
  const h = healthy();
  h.notifications = { pending_overdue: 12, oldest_pending_age_seconds: 7200, dead_letter: 4, dead_letter_24h: 2, expired_leases: 6 };
  h.security.failures_1h = 25;
  const keys = evaluateAlerts(h).map((x) => x.key).sort();
  assertEquals(keys, ['notifications_backlog', 'notifications_dead_letter', 'notifications_leases_expiring', 'security_failures']);
});

Deno.test('secret comparison fails closed', async () => {
  assertEquals(await secretMatches('x', ''), false);
  assertEquals(await secretMatches(null, 'x'), false);
  assertEquals(await secretMatches('wrong', 'right'), false);
  assertEquals(await secretMatches('right', 'right'), true);
});

Deno.test('provider receipt failures and unmatched receipts are warnings', () => {
  const h = healthy();
  h.notifications.receipt_failures_24h = 2;
  h.notifications.unmatched_receipts = 25;
  const a = evaluateAlerts(h);
  assertEquals(a.map((x) => x.key).sort(), ['notifications_receipt_failures', 'notifications_unmatched_receipts']);
  assertEquals(overallStatus(a), 'ok');
});
