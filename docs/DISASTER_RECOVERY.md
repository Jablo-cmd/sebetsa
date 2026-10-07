# Disaster recovery: evidence and runbooks

Evidence is labelled by where it was obtained (see [DOMAIN_STATUS.md](./DOMAIN_STATUS.md)). **No restore of the hosted Supabase project has been performed or observed, so no RPO or RTO is claimed.**

## 1. Backup and restore evidence

| Claim | Evidence | Status |
| ----- | -------- | ------ |
| The schema, data and security posture survive a logical dump and restore | `scripts/restore-drill.sh` against the migrated, populated local harness database: `pg_dump -Fc` 336 ms (900 KB), `pg_restore` into a fresh database 2.4 s; **66 tables / 116 rows** restored with identical row counts and content checksums; RLS + FORCE RLS on every table, no anon grants, all definer functions pin `search_path`, 118 policies present; `audit_log` still immutable after restore. | **GREEN — VERIFIED locally.** The dataset is a few hundred rows, so the timings say nothing about production volumes. |
| A database can be rebuilt from source | CI builds an empty PostgreSQL from `supabase/migrations` and runs every suite (26 suites + concurrency). | GREEN — VERIFIED (CI). |
| The hosted project is backed up | Plan, daily backup schedule, retention, PITR window | **BLOCKED — CANNOT VERIFY** without the live project. |
| A hosted restore works and how long it takes | Needs a restore of a backup/PITR point into a scratch project, timed | **BLOCKED — CANNOT VERIFY.** |
| Storage buckets are recoverable | `employee-documents` and `contract-documents` are **not** part of database backups | **BLOCKED / DECISION REQUIRED:** choose a separate copy (scheduled `rclone`/S3 sync or Supabase storage backups) and record it. |
| RPO / RTO | Cannot be set before a timed hosted restore | **BLOCKED.** Suggested starting targets once measured: RPO ≤ 15 min (PITR), RTO ≤ 4 h. |

Run the local drill after the RLS harness has populated its database:

```
RLS_DATABASE_URL=postgresql://postgres@localhost:55432/postgres?host=/tmp bash supabase/rls-tests/run.sh
SOURCE_URL='postgresql://postgres@localhost:55432/sebetsa_rls_test?host=/tmp' \
ADMIN_URL='postgresql://postgres@localhost:55432/postgres?host=/tmp' bash scripts/restore-drill.sh
```

### Hosted restore drill (to do, quarterly)

1. Create a scratch Supabase project; restore the latest backup or a PITR timestamp into it; **record the wall-clock time**.
2. Run the catalogue assertions of `supabase/rls-tests/tests/security_catalog.test.sql` against it (RLS/FORCE RLS everywhere, no anon grants, definer functions pinned).
3. Compare per-table row counts against the source.
4. Sign in as each role, open attendance and leave, open a document (signed URL).
5. Record RPO (age of the restore point) and RTO (time to a working restore) in this file with the date.

## 2. Scenarios

Common first steps: declare an incident owner; stop writes if data is at risk (put the app in maintenance by pausing the Pages deployment or revoking the anon key); note the time; preserve evidence (Supabase logs, `audit_log` `security` category, GitHub Actions history).

### Data corruption (bad migration, bad job, bad bulk edit)
1. Identify the window with `audit_log`, `job_runs` (which job, which tenant, `rows_affected`) and Supabase logs.
2. If scoped to a few rows: repair with a reviewed forward-only SQL fix. If broad: restore to a point before the window into a **scratch** project, then copy back only the affected rows (never overwrite production wholesale without a second person).
3. Jobs are idempotent and recorded, so a bad job run can be bounded by `job_runs.started_at` and re-run safely after the fix.
4. Add a regression test in `supabase/rls-tests/tests/` before closing.

### Accidental deletion
1. Tenant data deletes cascade from `organizations`; audit rows are immutable and survive row deletion, which shows who/what/when.
2. Restore the deleted rows from a PITR/backup restore in a scratch project, re-insert via SQL. Documents: restore the object from the separate storage copy (see §1; without one, deleted storage objects are unrecoverable).
3. Review who held the permission; consider whether a separation-of-duties rule is missing.

### Failed deploy
1. Migrations are forward-only. Before every production migration: restore point (PITR timestamp noted), apply to a branch/preview project first.
2. If the **app** build is bad: re-run the previous successful `main` workflow run (GitHub Pages deployments are static and re-deployable); no data impact.
3. If a **migration** is bad: do not edit it; write a new corrective migration, test it on the harness (`bash supabase/rls-tests/run.sh`), apply to a branch project, then production. Use PITR only if data was damaged.
4. The release gate blocks deploy when quality, Edge, RLS or E2E fail, so most bad deploys are stopped before they ship.

### Compromised credentials
1. **Browser/anon key:** low blast radius (RLS), but rotate if abused: Supabase → Project Settings → API; update the `VITE_SUPABASE_ANON_KEY` secret and redeploy.
2. **Service-role key** (full bypass): rotate immediately; redeploy Edge Functions; rotate `NOTIFICATIONS_DISPATCH_SECRET`, `OPS_HEALTH_SECRET`, `RESEND_WEBHOOK_SECRET`, provider keys (Resend, Twilio auth token).
3. **A user account:** `admin_set_user_status` to deactivate (bans the auth user and blocks the database for that profile); revoke sessions (`auth.admin.signOut`). Privileged roles need MFA, so a stolen password alone is not sufficient (see [MFA.md](./MFA.md)); review the user's `audit_log` rows.
4. **GitHub:** rotate repository/environment secrets; review the Actions log; all actions are SHA-pinned.
5. Review the `security` audit category for the exposure window; notify affected parties as POPIA/GDPR require.

### Regional outage (Supabase region or provider)
1. The application is stateless (static build + Supabase). Confirm via the Supabase status page and `uptime.yml` failures.
2. Hosted Supabase restores happen **in the same region by default**; cross-region recovery means restoring a backup into a project in another region (new URL/keys → rebuild the app with new `VITE_*` secrets) — plan and rehearse this; it is **not rehearsed**.
3. Notifications keep retrying (outbox with backoff, dead letter after 5 attempts); in-app notifications are unaffected. Scheduled jobs resume and are idempotent after recovery; `reconcile_receipts` applies provider receipts that arrived during the outage.
4. If the GitHub Pages host is down, the static build can be served from any static host with the same `VITE_*` values.

## 3. Assessment

| Area | Status |
| ---- | ------ |
| Logical restore fidelity and security posture after restore (local) | GREEN — VERIFIED |
| Rebuild from source | GREEN — VERIFIED (CI) |
| Hosted backups / PITR / restore time / RPO / RTO | BLOCKED — CANNOT VERIFY |
| Storage bucket recovery | BLOCKED — decision required |
| Scenario runbooks | AMBER — written, not rehearsed |
