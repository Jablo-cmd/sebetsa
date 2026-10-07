// Pure health/alert evaluation: no I/O, unit-tested with `deno test`.

export interface OpsHealth {
  database: string;
  jobs: { job: string; last_success_at: string | null; last_status: string | null; failures_since_success: number }[];
  jobs_never_ran: string[];
  notifications: {
    pending_overdue: number;
    oldest_pending_age_seconds: number;
    dead_letter: number;
    dead_letter_24h: number;
    expired_leases: number;
  };
  security: { failures_1h: number; events_24h: number };
}

export type Severity = 'critical' | 'warning';

export interface Alert {
  key: string;
  severity: Severity;
  message: string;
}

/** Thresholds, in one place so they are reviewable. */
export const THRESHOLDS = {
  jobFailuresSinceSuccess: 3, // repeated scheduled-job failures
  jobStaleHours: { default: 30, escalate_overdue: 1, audit_retention: 24 * 8 } as Record<string, number>,
  pendingOverdue: 10, // notifications waiting longer than 15 minutes
  oldestPendingSeconds: 60 * 60,
  deadLetter24h: 1, // any message newly given up on
  expiredLeases: 5, // workers dying mid-delivery
  securityFailures1h: 10, // e.g. repeated permission/MFA refusals
} as const;

export function evaluateAlerts(h: OpsHealth, now: Date = new Date()): Alert[] {
  const alerts: Alert[] = [];

  for (const j of h.jobs) {
    if (j.failures_since_success >= THRESHOLDS.jobFailuresSinceSuccess) {
      alerts.push({ key: `job_failing:${j.job}`, severity: 'critical', message: `Scheduled job ${j.job} failed ${j.failures_since_success} times since its last success` });
    }
    const limit = THRESHOLDS.jobStaleHours[j.job] ?? THRESHOLDS.jobStaleHours.default;
    if (j.last_success_at && now.getTime() - new Date(j.last_success_at).getTime() > limit * 3600_000) {
      alerts.push({ key: `job_stale:${j.job}`, severity: 'warning', message: `Scheduled job ${j.job} has not succeeded in over ${limit}h` });
    }
  }
  if (h.jobs_never_ran.length > 0) {
    alerts.push({ key: 'jobs_not_scheduled', severity: 'warning', message: `Scheduled jobs never ran: ${h.jobs_never_ran.join(', ')} (is pg_cron enabled and schedule_platform_jobs() run?)` });
  }

  const n = h.notifications;
  if (n.pending_overdue >= THRESHOLDS.pendingOverdue || n.oldest_pending_age_seconds >= THRESHOLDS.oldestPendingSeconds) {
    alerts.push({ key: 'notifications_backlog', severity: 'critical', message: `${n.pending_overdue} notification deliveries waiting (oldest ${Math.round(n.oldest_pending_age_seconds / 60)} min): is the dispatcher scheduled and configured?` });
  }
  if (n.dead_letter_24h >= THRESHOLDS.deadLetter24h) {
    alerts.push({ key: 'notifications_dead_letter', severity: 'critical', message: `${n.dead_letter_24h} notification deliveries gave up in the last 24h (${n.dead_letter} in total)` });
  }
  if (n.expired_leases >= THRESHOLDS.expiredLeases) {
    alerts.push({ key: 'notifications_leases_expiring', severity: 'warning', message: `${n.expired_leases} delivery leases expired without completing (workers dying?)` });
  }

  if (h.security.failures_1h >= THRESHOLDS.securityFailures1h) {
    alerts.push({ key: 'security_failures', severity: 'critical', message: `${h.security.failures_1h} failed security events in the last hour` });
  }
  return alerts;
}

/** Overall status: any critical alert means degraded service worth waking someone for. */
export function overallStatus(alerts: Alert[]): 'ok' | 'degraded' {
  return alerts.some((a) => a.severity === 'critical') ? 'degraded' : 'ok';
}

/** Constant-time-ish secret check (hash first so length does not leak); empty secret never matches. */
export async function secretMatches(supplied: string | null, expected: string): Promise<boolean> {
  if (!expected || !supplied) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(supplied)),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ]);
  const x = new Uint8Array(a);
  const y = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}
