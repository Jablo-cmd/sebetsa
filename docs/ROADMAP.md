# Next-generation roadmap and gap analysis

Written after the stabilisation pass, against the code as it stands. It describes what exists, what is missing, and a prioritised order for building. Nothing here is built unless [DOMAIN_STATUS.md](./DOMAIN_STATUS.md) says so.

## 0. Gaps in what already exists (do these first)

| # | Gap | Why it matters | Effort |
| - | --- | -------------- | ------ |
| 1 | ~~MFA is not enforced server-side~~ — done, see `MFA.md`; live verification pending | — | — |
| 2 | No frontend error reporting, uptime probe or worker alerting (`BCDR_OBSERVABILITY.md`) | Failures would be invisible in production. | S–M |
| 3 | Live-environment verification has not happened (RLS state, backups, secrets, provider delivery, branch protection) | Source cannot prove hosted state. | M, blocked on access |
| 4 | ~~Quiet hours are evaluated in UTC~~ — done: per-user IANA zone, organisation fallback, UTC last | — | — |
| 5 | ~~No provider delivery receipts~~ — implemented (signed, idempotent webhook + reconciliation), not live verified | — | — |
| 6 | Audit retention is now a scheduled, self-auditing job (activates with pg_cron); nobody is yet assigned to review the security category | An owner is an organisational decision. | S |
| 7 | Runtime dependencies are clean (`supabase-js` 2.117.2, `react-router` 7). Build/test tooling still has advisories needing vite 8 / vitest 5 / tailwind 4 (see `SECURITY_MODEL.md` §8) | Dev-only exposure; do on a dedicated branch. | M |
| 8 | Select fields in forms announce errors via `role="alert"` but are not programmatically tied with `aria-describedby` | Minor a11y debt. | S |
| 9 | ~~GitHub Actions pinned by tag~~ — now pinned to commit SHAs; Dependabot keeps them current. Branch protection still unverified | Needs repository admin. | S |
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

## 1a. Offline support — architectural readiness assessment (assessment only; nothing is built)

**Verdict: NOT READY. Sebetsa does not support offline use and does not claim to.** What exists is honest status, not capability: `OfflineBanner` on field-critical pages and `retryOnNetworkError` (seconds-long retries of transient failures; nothing is persisted).

| Dimension | Finding | Consequence |
| --------- | ------- | ----------- |
| App shell | No service worker, no web manifest, no precache; `public/` holds only a favicon. E2E blocks service workers. | A cold start with no network shows nothing. A PWA shell is the prerequisite for everything else. |
| Data layer | Services call Supabase directly per page; no shared cache, no IndexedDB, no query layer. | There is no local copy of rosters, tasks or sites to read offline; a read-through cache (and a decision on what may be stored on a device) must come first. |
| Writes | Direct table writes and RPCs (`clock_in`, `clock_out`, `complete_task`, `submit_leave_request`); no client-generated operation id, no idempotency key (the only idempotency is domain-level, e.g. one open break per record, one task per template period). | A queued write replayed after a network blip can duplicate or conflict. Each queued operation needs a client-generated UUID that the RPC treats as an idempotency key. |
| Time | Attendance timestamps are taken server-side (`now()`); an offline clock-in has only the device clock. | Offline attendance requires a trusted-time policy (device time recorded as claimed, server time as received, a tolerance, and a review flag) and, for GPS-verified presence, the geofence design in P3. |
| Conflicts | Workflow state machines and separation-of-duties guards run in the database. A queued action can arrive after the record changed (task reassigned, shift cancelled, leave decided). | The database already rejects invalid transitions; the client needs a visible "rejected on sync, here is why" path and a rule for who resolves it. |
| Auth | Supabase sessions refresh over the network; MFA step-up (aal2) is required for privileged roles and enforced by the database. | Offline access must be limited to low-privilege field roles; privileged operations stay online-only. Long offline spells outlive access tokens — decide the offline grace window and re-auth on reconnect. |
| Security | Local storage of rosters, names and evidence photos puts personal data on devices. | Needs encryption-at-rest posture (platform storage limits), remote wipe on deactivation (a deactivated user's queued writes must be refused on sync — already true in the database), retention limits, and a POPIA review. |
| Files | Evidence and document upload is two-step (database slot, then bytes). | Needs a resumable upload queue with slot reservation and cancel-on-abandon. |
| Testing | Service workers are blocked in the harness; the fake backend cannot simulate partial sync. | Build a service-worker-aware harness with deterministic offline/online switching before any queue code. |

**Recommended order** (when/if prioritised, after P2 duties): (1) PWA shell + read-only cache of the signed-in user's own schedule and tasks; (2) client operation ids and idempotent RPCs for `clock_in`/`clock_out`/`complete_task`; (3) a persisted write queue with visible sync status and rejection handling for those three actions only; (4) evidence upload queue; (5) trusted-time and geofence rules (P3). Do not queue any privileged or approval action.

## 1b. Command Centre — implementation plan (plan only; **not implemented**)

Written after the production-readiness pass. Build only after the production certification gate in `DOMAIN_STATUS.md` has no RED row.

**Business value.** One live view of the working day for operations: who is on shift, who is late or absent, open critical incidents, overdue and escalated tasks, expiring compliance, and SLA breaches in progress, with drill-down to the record that needs action. Success measures: time to notice a missed shift or critical incident, share of escalations acknowledged within SLA, fewer manual report requests.

**User roles.**

| Role | Sees | Acts |
| ---- | ---- | ---- |
| Operations manager, organisation administrator | Whole tenant, filterable by region/client/contract/site | Reassign, escalate, open records |
| Regional manager, site manager, supervisor | Only their scope (existing `user_scopes` + restrictive policies) | Same, inside scope |
| HR | Workforce exceptions (absence, expiring qualifications, documents), no operational incidents beyond what RLS already grants | Open records |
| Employee, client user | No Command Centre | — |

**Dashboard metrics** (each defined once, in SQL, versioned): shifts today (scheduled / started / late / no-show / unfilled); clock-ins vs scheduled; open incidents by severity and age; tasks overdue / escalated / due next 4 h; compliance expiring in 7/30 days; SLA measurements below threshold or projected to breach; notification backlog and failed deliveries (operational health strip, from `ops_health()` for administrators only).

**Database and query requirements.** Read-only `SECURITY INVOKER` functions returning pre-aggregated rows (never owner-owned views, which bypass RLS), one per panel, taking region/client/contract/site/date filters; keyset pagination for lists; indexes proven by `EXPLAIN` on `(site_id, starts_at)`, `(status, due_at)`, `(tenant_id, status, severity)` and any the plans show missing; no per-row RPC calls (avoid N+1); a single batched call per panel. Counters that are expensive at scale move to a refresh-on-schedule summary table written by a `run_scheduled_job` job and read through RLS-protected functions; decide per panel from measured timings.

**RLS and security.** No new privileges and no new tables readable by new audiences: every function runs as the caller so scope, tenant and MFA enforcement apply unchanged. Add a leakage suite: each scoped role against a two-tenant, multi-region fixture proves it receives only its own rows and counts (counts must not leak existence of out-of-scope records). Alerts rows link to records the viewer can already open.

**Performance.** Budgets taken from the measured baseline in `docs/PERFORMANCE.md`: panel query p95 within the page budget at the stated dataset size; total payload per refresh bounded; refresh interval ≥ 30 s with a visible "as of" time and backoff when the tab is hidden; load test with the same harness at 2× the baseline dataset before release.

**Mobile.** Summary-first stacked cards, one-tap drill-down, large touch targets, no horizontal scroll at phone width; critical exceptions first; call/message the supervisor from a card.

**Accessibility.** Status never colour-only; live regions announce changes politely and sparingly (no announcement per refresh); keyboard-reachable drill-downs; axe sweep per role in the E2E suite; respects reduced motion.

**Alerting.** Panels reuse the existing alert definitions (`ops-health` thresholds) for platform health; business exceptions (no-show, critical incident open > N minutes, SLA breach) become in-app notifications through `create_notification`, so quiet hours, channel preferences, the outbox and receipts apply; escalation is a scheduled job with the same idempotency/once-only guarantees as `escalate_overdue`.

**Reporting.** CSV export of each panel through the existing export path (RLS-scoped); a daily operations summary job is a later increment.

**E2E.** Per-role scenarios on the fake backend (scoped manager sees only scope; empty/error/loading states; drill-down opens the right record); mobile viewport; axe; fault injection for each panel (a failed panel shows an error and does not blank the page).

**Operational risks.** Query cost on large tenants (mitigate: measure first, summary tables, filters required above a size); stale data presented as live (always show "as of"); alert fatigue (thresholds reviewed with operations, grouped); privilege leakage through aggregates (leakage suite is a release gate); dependence on the schedule being enabled (the health endpoint alerts when jobs have not run).

**Suggested increments.** (1) Shifts-today and exceptions panels for managers, with the leakage suite; (2) incidents/tasks/compliance panels; (3) SLA panel; (4) operational-health strip; (5) in-app alerting for business exceptions.

## 2. Suggested sequence

1. Section 0 gaps 1, 2, 6, 11 (security and operability) — small, unblock everything else.
2. P2 (duties) → P1 (command centre) → P5 (SLA intelligence).
3. P4 (client portal) once the leakage suite exists.
4. P3 (field/GPS/offline) after a privacy review; build the offline test harness first.
5. P7/P8/P9 in parallel as capacity allows.
6. P6 and P10 only after explicit data-protection decisions.
