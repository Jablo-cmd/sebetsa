# Business continuity, disaster recovery and observability

An honest assessment. Sebetsa is a client application plus a hosted Supabase project; almost everything that matters for recovery lives in the hosted project and cannot be proven from this repository. **Nothing below has been tested against a live environment.**

## What the repository gives you

| Capability | State |
| ---------- | ----- |
| Schema reproducibility | Every schema change is a migration; CI builds an empty database from them and runs the regression suites, so a database can be rebuilt from source. |
| Application rebuild | `npm ci && npm run build` is deterministic from the lockfile; deploy is a static build to GitHub Pages. |
| Idempotent background work | The notification outbox uses atomic claims with leases, bounded retries, exponential backoff and a dead-letter state; a crashed worker's rows are re-claimed. |
| Audit trail | Append-only, categorised, retained ≥ 1 year by rule (default 7). |
| Structured worker logs | `notifications-dispatch` writes one JSON line per event with counts only. |

## What must be done in the live environment (not done, not verifiable here)

1. **Backups and point-in-time recovery.** Confirm the Supabase plan includes PITR, set the retention window, and record it. Storage buckets (`employee-documents`, `contract-documents`) are *not* covered by database backups — decide on a separate copy.
2. **Define and test RPO/RTO.** Suggested starting targets for a workforce-operations system: RPO ≤ 15 minutes, RTO ≤ 4 hours. Write them down only once a restore has been timed.
3. **Restore drill.** Restore the latest backup into a scratch project, run `supabase/rls-tests` assertions that apply to live data (catalogue checks: RLS on every table, no anon grants), log in, and open a payroll-critical path (attendance, leave). Do this quarterly.
4. **Migration failure recovery.** Migrations are forward-only. Before each production migration take a restore point, apply in a branch/preview project first, and keep the previous app build deployable (GitHub Pages deployments can be re-run from a previous commit).
5. **Credential compromise.** Runbook: rotate the Supabase service-role key and anon key, rotate `NOTIFICATIONS_DISPATCH_SECRET` and provider keys, revoke sessions (`auth.admin.signOut`), review the `security` audit category for the window, notify as required.
6. **Hosting / domain recovery.** The site deploys to GitHub Pages; a custom domain, if any, and its DNS records must be documented by whoever owns them. No production domain is assumed in this repository.
7. **Provider outage.** If Resend or Twilio is down, deliveries retry with backoff and dead-letter after five attempts; in-app notifications are unaffected. Add an alert on `dead_letter` growth.

## Observability gaps

- **No frontend error reporting.** Uncaught client errors are not collected anywhere. Add an error tracker (and a React error boundary that reports) before go-live.
- **No uptime or synthetic checks.** Add a probe of the app URL and a Supabase health/auth check.
- **No database or API metrics wired in.** Use Supabase's built-in reports and log drains; alert on error-rate, slow queries, connection saturation and storage growth.
- **Worker alerting.** Count of `pending` deliveries older than 15 minutes and of `dead_letter` rows should page someone; both are single queries on `notification_deliveries`.
- **Audit review.** Nobody is yet assigned to review the `security` category; define an owner and cadence.
- **Request correlation.** `audit_log.request_id` is populated from `x-request-id` when a gateway sets it; the browser does not currently generate one.

## Assessment

| Area | Status |
| ---- | ------ |
| Rebuild from source | GREEN (verified in CI) |
| Backups, PITR, restore drill | BLOCKED — needs the live project |
| RPO / RTO | BLOCKED — cannot be set before a restore is timed |
| Frontend/error observability | RED — absent |
| Worker observability | AMBER — structured logs exist; no alerts |
| Incident runbooks | AMBER — outlined above and in `SECURITY.md`; untested |
