# Operating Sebetsa: health, alerts, scheduled jobs

What exists in the repository, what it does, and the exact external steps still needed. Nothing here has been run against a live environment.

## 1. Error visibility

| Layer | Mechanism | State |
| ----- | --------- | ----- |
| Browser | `src/lib/errorReporting.ts` captures uncaught errors, unhandled rejections and React render errors (`ErrorBoundary`). Reports carry message, stack, route path (ids masked, no query/hash), version, time. Tokens, JWTs, passwords, emails, phone numbers, long opaque strings and key=value secrets are scrubbed first; the report is deduplicated (60 s) and capped (20 per session); it is sent with `credentials: 'omit'`. | IMPLEMENTED, unit-tested. **Sends nothing until `VITE_ERROR_REPORT_URL` is set** — that endpoint is the integration boundary (a Sentry-compatible relay, an Edge Function, a log drain). NOT LIVE VERIFIED. |
| Edge Functions | One structured JSON line per event with counts only (`batch_complete`, `claim_failed`, `unauthorized`, `health_check`, `health_check_failed`). Read them in Supabase → Edge Functions → Logs. | IMPLEMENTED. |
| Database | Postgres and API logs in the Supabase dashboard; `audit_log` (category `security`) for security events; `job_runs` for scheduled work. | IMPLEMENTED (data), dashboards are external. |

## 2. Health checks

- **App:** `uptime.yml` fetches `APP_URL` every 15 minutes.
- **Backend / API:** `ops-health` Edge Function (`GET`). Without a secret it returns only `{status}` (`200 ok`, `503 degraded`). With `x-health-secret: <OPS_HEALTH_SECRET>` it also returns the alerts and the counts behind them. It calls `ops_health()` (service role only, counts and ages, no personal data). A database failure is reported as `degraded`.
- **Background workers:** the same snapshot reports scheduled-job success/failure/staleness and notification outbox backlog, dead letters and expired leases.

Setup: `supabase functions deploy ops-health`, `supabase secrets set OPS_HEALTH_SECRET=…`, then set repository variables `APP_URL`, `HEALTH_URL` (`https://<ref>.supabase.co/functions/v1/ops-health`) and the secret `OPS_HEALTH_SECRET`. **Until the variables are set the workflow says "nothing was probed" and passes; it never reports an unchecked system as healthy in its log.** Not live verified.

## 3. Alerts

Rules live in `supabase/functions/ops-health/logic.ts` (`THRESHOLDS`, `evaluateAlerts`) and are unit-tested.

| Condition | Alert key | Severity |
| --------- | --------- | -------- |
| App not serving / backend unreachable | uptime workflow fails | critical |
| Any scheduled job failed ≥ 3 times since its last success | `job_failing:<job>` | critical |
| A scheduled job has not succeeded within its window (30 h; escalation 1 h; audit retention 8 d) | `job_stale:<job>` | warning |
| Jobs never ran (pg_cron not enabled / not scheduled) | `jobs_not_scheduled` | warning |
| ≥ 10 deliveries pending > 15 min, or oldest > 1 h | `notifications_backlog` | critical |
| Any delivery gave up (dead letter) in 24 h | `notifications_dead_letter` | critical |
| ≥ 5 delivery leases expired unfinished | `notifications_leases_expiring` | warning |
| ≥ 10 failed security events in 1 h | `security_failures` | critical |

Delivery of the alert is the failing `uptime.yml` run (GitHub emails watchers) — deliberately lightweight. To route to Slack/PagerDuty/email, add a notification step to that workflow using a webhook secret, or point any external monitor at `HEALTH_URL` and alert on non-200. **Not configured; owner and channel must be chosen.**

## 4. Scheduled jobs

Entry point `run_scheduled_job(name)` (service role / pg_cron only). Jobs: `recurring_tasks`, `escalate_overdue`, `expire_documents`, `expire_compliance`, `expire_qualifications`, `audit_retention`.

- **Idempotent and retry-safe:** one task per template per period; escalation only moves `open/in_progress` tasks to `escalated` once (one notification); expiry sweeps flip a row once; retention deletes only rows past the window.
- **Concurrency:** a job-wide advisory lock; an overlapping run records `skipped_locked` and exits. Template rows are locked while generating.
- **Failure isolation:** each tenant runs in its own sub-transaction; a failing tenant is recorded in `job_runs` (`failed`, truncated error) and the rest continue.
- **Observability:** `job_runs` (tenant administrators read their tenant's rows; platform administrators everything), `job_health()`, `ops_health()`.
- **Least privilege:** the runner and the internal `job_*` functions are executable by `service_role` only; the manager RPCs remain thin permission wrappers. `purge_audit_log` stays service-role only and refuses windows under 365 days.
- **Schedule:** `schedule_platform_jobs()` registers pg_cron entries (recurring 00:05, escalation every 15 min, expiry sweeps 00:15–00:25, retention Sunday 02:30; times are UTC). The migration calls it only when pg_cron is installed. **To activate: enable the `pg_cron` extension in the Supabase dashboard, then run `select public.schedule_platform_jobs();`.** Not live verified.
- **Tests:** `supabase/rls-tests/tests/scheduled_jobs.test.sql`, `ops_health.test.sql`.

## 5. Audit governance

- Retention: `audit_retention` job (weekly), default window 7 years, minimum 365 days, every run writes a `security` audit event `audit_retention_run` with the deleted count.
- Separation: `business` vs `security` category; immutable (UPDATE/DELETE/TRUNCATE blocked except the retention path).
- Review: the security category is queryable by organisation administrators and platform administrators (RLS) and surfaced through `ops_health().security`. **A named reviewer and cadence must be assigned by the organisation** (suggested: weekly review of `category = 'security'`, immediate review on a `security_failures` alert).
