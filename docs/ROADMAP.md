# Next-generation roadmap and gap analysis

Written after the stabilisation pass, against the code as it stands. It describes what exists, what is missing, and a prioritised order for building. Nothing here is built unless [DOMAIN_STATUS.md](./DOMAIN_STATUS.md) says so.

## 0. Gaps in what already exists (do these first)

| # | Gap | Why it matters | Effort |
| - | --- | -------------- | ------ |
| 1 | ~~MFA is not enforced server-side~~ — done, see `MFA.md`; live verification pending | — | — |
| 2 | No frontend error reporting, uptime probe or worker alerting (`BCDR_OBSERVABILITY.md`) | Failures would be invisible in production. | S–M |
| 3 | Live-environment verification has not happened (RLS state, backups, secrets, provider delivery, branch protection) | Source cannot prove hosted state. | M, blocked on access |
| 4 | ~~Quiet hours are evaluated in UTC~~ — done: per-user IANA zone, organisation fallback, UTC last | — | — |
| 5 | No provider delivery receipts / bounce handling | A message can be "sent" and never arrive. | M |
| 6 | Audit retention is now a scheduled, self-auditing job (activates with pg_cron); nobody is yet assigned to review the security category | An owner is an organisational decision. | S |
| 7 | `react-router` is on v7 now; `@supabase/supabase-js` is pinned at 2.45.4 and carries two low advisories in `auth-js` | Upgrade after the next full E2E on a branch. | M |
| 8 | Select fields in forms announce errors via `role="alert"` but are not programmatically tied with `aria-describedby` | Minor a11y debt. | S |
| 9 | GitHub Actions are pinned by version tag, not commit SHA | SHA pinning needs verified SHAs from upstream; Dependabot is configured to keep them current. | S |
| 10 | Region/client/site/contract create is not atomic with their links in every case (a contract is kept if linking its sites fails; the user is told) | Rare partial state. | S (`create_contract` RPC) |
| 11 | Scheduled jobs are implemented (`run_scheduled_job`, `schedule_platform_jobs()`); activation needs pg_cron on the live project, and the delivery dispatcher still needs its own schedule | Operations depend on enabling the schedule. | S |

## 1. Product roadmap

Priority order is by operational value ÷ risk, subject to dependencies. Each item lists value, dependencies, database, security, UI, mobile, reporting, testing and risk.

### P1 — Command centre
*Value:* one live view of the day: who is on shift, who is late/absent, open critical incidents, overdue tasks, SLA breaches in progress. The dashboard exceptions row is the seed.
*Depends on:* gap 11 (scheduled jobs), scope model (already in place).
*Database:* read-only views as `SECURITY INVOKER` functions (never owner-owned views — they bypass RLS); indexes on `(site_id, starts_at)`, `(status, due_at)`.
*Security:* everything inherits scope RLS; no new privileges.
*UI:* site grid with drill-down; filters by region/client/contract; auto-refresh.
*Mobile:* summary-first cards; one-tap call/message supervisor.
*Reporting:* shift-fill rate, lateness, response times.
*Testing:* fake-backend scenarios per scoped role; axe; load test of the queries.
*Risk:* query cost on large tenants — measure before shipping.

### P2 — Cleaning duties and schedules
*Value:* the core of the business — recurring duty plans per site/area (frequency, checklist, SLA link, evidence rules) generating dated work instead of ad-hoc tasks.
*Depends on:* task templates and recurring generation (exist), create-task RPC (exists), scheduled jobs.
*Database:* `site_areas`, `duty_plans`, `duty_plan_items`, generated `tasks` link back to the plan; unique `(plan_item, period)` for idempotent generation.
*Security:* manage via operations roles; scoped read; SoD already covers verification.
*UI:* plan builder, per-site calendar, exception handling (skipped/rescheduled with reason).
*Mobile:* first-class — tick-off, photo evidence, offline queue (see P3).
*Reporting:* duty completion by site/plan, missed-duty trend feeding SLA.
*Testing:* generation idempotency in RLS suite; E2E plan→task→verify.
*Risk:* modelling variety of real duty regimes; start with weekly patterns.

### P3 — Field workforce: GPS, geofencing, tours, offline
*Value:* proof of presence and of rounds, not just self-declared clock-ins.
*Depends on:* P2, privacy review.
*Database:* `site_geofences`, `clock_events` with location and accuracy, `tour_checkpoints`/`tour_scans`; location data minimised and retention-limited.
*Security:* employee consent and notice; location only at clock/scan time; only managers in scope can read; audit access.
*UI:* geofence editor; exception review ("clocked in outside fence").
*Mobile:* PWA with a local write queue and conflict rules; QR/NFC checkpoints; low-bandwidth mode.
*Reporting:* presence verified vs declared; tour completion.
*Testing:* offline/online transitions need a different harness (service-worker) — currently blocked by the suite's `serviceWorkers: 'block'`.
*Risk:* highest — privacy law (POPIA), device variance, battery, spoofing.

### P4 — Client portal
*Value:* clients see their sites' service, incidents, SLA performance and sign-offs.
*Depends on:* the `client_user` role exists but has no data access by design; needs a client↔user binding.
*Database:* `client_users(profile_id, client_id)`; client-scoped read policies on a curated set of tables/views; no direct table access.
*Security:* strictest review — a new tenant-external audience; separate RLS tests proving a client sees only its own client; no employee personal data.
*UI:* read-mostly dashboards, incident raise, sign-off of completed work, document download.
*Mobile:* responsive.
*Reporting:* monthly service report PDF per contract.
*Testing:* dedicated cross-client leakage suite.
*Risk:* data leakage — gate on the leakage suite.

### P5 — SLA intelligence
*Value:* from monthly "compute" button to continuous measurement, breach prediction and credits.
*Depends on:* P1, P2, scheduled jobs.
*Database:* scheduled `compute_sla_measurement`, thresholds with warning bands, breach events, optional service-credit rules.
*Security:* unchanged (definer function already checks the caller).
*UI:* contract SLA dashboard, breach timeline, drill into the failing tasks/shifts.
*Reporting:* breach history, root-cause categories.
*Testing:* property tests on measurement windows; RLS test per metric.
*Risk:* contractual disputes over definitions — keep the formulas documented and versioned.

### P6 — Commercial intelligence
*Value:* margin per contract/site — labour hours × cost vs contract value; renewal pipeline.
*Depends on:* payroll rates (not modelled), contract values (not modelled).
*Database:* contract value/billing terms; employee cost rates with strict visibility; computed margin views.
*Security:* **new sensitive data class (pay rates)** — separate permission, audit on read, no scope bypass.
*UI/Reporting:* margin, utilisation, expiring contracts.
*Risk:* high sensitivity; do not start without a data-protection decision.

### P7 — Procurement and inventory depth
*Value:* approvals exist; missing supplier management, purchase orders, goods received, reorder points, per-site stock take.
*Depends on:* existing procurement/inventory, SoD (`procurement.decide`).
*Database:* suppliers, POs, receipts; reorder levels; stock-count sessions.
*Security:* approval limits by role; receipts by someone other than the requester (new SoD rule).
*Testing:* ledger invariants (balance = sum of movements) in the RLS suite.
*Risk:* medium.

### P8 — Asset lifecycle depth
*Value:* maintenance log exists; add preventive schedules, QR labels, depreciation-free usage and downtime reporting, linked to duty plans (equipment per duty).
*Database:* maintenance plans and due dates; asset↔duty links.
*Mobile:* QR scan to report fault.
*Risk:* low.

### P9 — Workforce intelligence
*Value:* absence patterns, overtime, qualification expiry forecasting, skills coverage per site, fatigue/hours limits.
*Depends on:* attendance, leave, skills (all exist).
*Security:* aggregate-by-default; individual-level views behind HR permission and audit.
*Reporting:* the primary output.
*Risk:* fairness/bias if used for decisions — keep it descriptive, human-reviewed.

### P10 — AI layer
*Value:* assisted scheduling suggestions, plain-language questions over operational data, incident summarisation.
*Depends on:* P1–P9 data quality, a data-protection decision, an approved provider.
*Security:* the model must act **as the caller** (their RLS), never with a service key; no personal data to external providers without a contract; every suggestion explainable and overridable; prompts/outputs audited.
*Testing:* evaluation sets; prompt-injection tests through free-text fields (incident descriptions, notes).
*Risk:* highest governance risk; last.

## 2. Suggested sequence

1. Section 0 gaps 1, 2, 6, 11 (security and operability) — small, unblock everything else.
2. P2 (duties) → P1 (command centre) → P5 (SLA intelligence).
3. P4 (client portal) once the leakage suite exists.
4. P3 (field/GPS/offline) after a privacy review; build the offline test harness first.
5. P7/P8/P9 in parallel as capacity allows.
6. P6 and P10 only after explicit data-protection decisions.
