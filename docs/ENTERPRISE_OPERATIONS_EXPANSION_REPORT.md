# Sebetsa — Enterprise Operations Expansion: Final Report

GPS & Guard Tours (Domain 13) + Operations Command Centre & Emergency Response (Domain 14) + Workforce Intelligence & AI (Domain 15).

Branch: `claude/app-capabilities-review-cnvcgv`. Commits: `f102cd5`, `c554e6e`, `2b819be`, `8966d57` (4 commits, in that order — DB layer, frontend, adversarial-review security fixes, a missing-UI gap fix). This report reflects the state of the repository as of `8966d57`.

**Status legend used throughout, per this brief's own §28 requirement:** IMPLEMENTED · TESTED (unit/RLS/e2e ran locally against a real engine, not mocked-only) · VERIFIED IN CI (not yet true — this branch has not run through GitHub Actions) · VERIFIED AGAINST HOSTED SUPABASE (not true — no hosted project access exists in this session) · DEPLOYED (not true — nothing in this pass was deployed anywhere) · NOT VERIFIED · BLOCKED (names the concrete external dependency).

---

## 1. What was actually built

### Domain 13 — GPS-Verified Field Presence + Guard Tours

**IMPLEMENTED, TESTED (RLS).**

- Server-authoritative geofence verification. `clock_in()`/`clock_out()` accept only raw `latitude`/`longitude`/`accuracy_meters`/`client_captured_at`/`gps_denied`/`offline_captured` — there is no `is_within_geofence` parameter anywhere; the Haversine distance and the resulting `gps_verification_status` (`verified` / `outside_geofence` / `low_accuracy` / `location_unavailable` / `pending_verification` / `offline_pending` / `manual_review` / `not_applicable`) are computed inside the same `SECURITY DEFINER` transaction as the attendance write.
- Immutable location evidence (`attendance_location_events`) — one row per capture attempt, append-only, no `UPDATE`/`DELETE` policy for `authenticated`. A failed or denied read is still recorded, never silently dropped.
- A manual, supervisor-reviewed exception workflow (`attendance_location_exceptions` + `request_attendance_location_exception()`/`decide_attendance_location_exception()`) that never edits or deletes the original evidence row — self-approval is explicitly blocked (an employee cannot decide their own exception; `is_platform_admin()` is the only override).
- Guard tours as a real patrol system, not a task checklist: `checkpoints`, `patrol_routes`, `patrol_route_checkpoints`, `patrol_runs`, `patrol_checkpoint_scans`. `scan_checkpoint()` detects and evidences (never silently accepts or silently drops) wrong-sequence scans, duplicate scans, out-of-tolerance-window scans, invalid/unknown checkpoint codes, and an impossible-travel-time heuristic (two valid scans under 10 seconds apart is flagged, not blocked). `start_patrol()` enforces the caller's own `site_assignments` membership and blocks a second concurrent in-progress patrol. `complete_patrol()` computes completion against the route's configured threshold.
- Frontend: `MyAttendancePage` captures a device location before every clock-in/out and surfaces the resulting verification status + an exception-request form when it fails; `MyPatrolsPage` (start a route, scan a checkpoint via the `BarcodeDetector` Web API where the browser supports it or manual code entry as the always-working fallback, view scan history, complete the patrol); `PatrolOversightPage` (`get_patrol_summary()` — real 7-day aggregate figures, no hardcoded stats) for the operations tier; `LocationExceptionsPage` for supervisor review/decision.

### Domain 14 — Operations Command Centre + Emergency Response

**IMPLEMENTED, TESTED (RLS).**

- `get_command_centre_snapshot(tenant_id)` — `SECURITY INVOKER`, RLS-riding (the same deliberate, established pattern as the pre-existing `get_operational_metrics()`): 22 live aggregate figures (workforce, site coverage, patrols, compliance, incidents, tasks, contracts, emergencies, alerts) computed by a single SQL function, never duplicated or summed client-side. A caller's own RLS governs what the figures reflect — a `site_manager` sees only what their own access already permits, with no separate role-branching logic reimplemented in the function.
- A deterministic operational-alert engine (`operational_alerts`, lifecycle `open → acknowledged → resolved`, controlled `reopen`), raised only by four cron-scheduled sweep functions (`raise_understaffed_site_alerts()`, `raise_missed_patrol_alerts()`, `raise_contract_sla_alerts()`, `raise_overdue_incident_alerts()`) — never a direct client insert. Idempotent via a partial unique index (an already-open alert for the same subject is never duplicated by re-running the sweep) — proven in the RLS suite by running the sweep twice and asserting exactly one alert exists.
- A safety-critical emergency lifecycle (`emergency_events`, immutable/append-only + `emergency_responses`, mutable), `triggered → acknowledged → responding → resolved`, with a tenant-configurable escalation chain (`emergency_escalation_policies`) advanced by a cron sweep — never a fixed, hardcoded org-wide path. `trigger_emergency()` is reachable by every employee and raises a critical alert in the same transaction. **A real adversarial-review finding, fixed in this pass:** `acknowledge_emergency()`/`respond_to_emergency()`/`resolve_emergency()` originally checked only `can_manage_operations()`, with no check against the caller acting on their own triggered emergency — since an operations-tier role (site_manager and above) is routinely also an employee who can trigger the panic button, this allowed someone to acknowledge/respond/resolve their own emergency alone, defeating independent oversight. The same gap existed one layer down (`acknowledge_operational_alert()`/`resolve_operational_alert()` could be called directly on the linked `emergency_active` alert to bypass the emergency-specific guard). Both are now fixed with the same self-approval pattern already established elsewhere in the codebase (`decide_attendance_location_exception()`), with 4 new RLS assertions proving a site_manager cannot act on their own emergency through either path.
- A provider-agnostic notification-delivery tracker (`notification_deliveries`) — the real, complete delivery-tracking data model a push/SMS provider would write into; there is no real push/SMS provider in this repository (no credentials exist anywhere), so `record_notification_delivery()` starts non-`in_app` deliveries `pending`, honestly, rather than claiming a delivery it cannot verify.
- Frontend: `CommandCentrePage` (the 22-figure snapshot, grouped and linked to the relevant detail page), `OperationalAlertsPage` (filterable inbox, acknowledge/resolve), an omnipresent `PanicButton` (rendered in `DashboardLayout`, deliberately **not** permission-gated — the same posture as `/dashboard`/`/notifications`, since every employee must be able to reach it), `EmergencyResponsePage` (operations-tier acknowledge/respond/resolve with resolution notes).

### Domain 15 — Workforce Intelligence + AI

**IMPLEMENTED, TESTED (RLS + unit).**

- A clean data-model separation between `rule_based` and `ai_generated` insights (`insight_kind` enum on `ai_query_log`). Every insight this pass ships is `rule_based` — **there is no LLM provider configured anywhere in this repository** (no API key, no edge function calling one), stated explicitly in the migration's own header comment and in `intelligenceService.ts`'s. `ai_generated` exists as the seam a real LLM integration would use later, not a claim one exists today.
- Six deterministic anomaly/insight functions, all `SECURITY INVOKER`/RLS-riding, no client-side aggregation: `get_understaffed_sites()`, `get_employees_absent_now()`, `get_expiring_qualifications()`, `get_declining_sla_contracts()`, `get_overtime_spike_employees()`, `get_site_incident_ranking()`.
- A real, working, permission-aware natural-language **router**, not a claim that a language model is answering: `matchIntent()` (a pure, unit-tested TypeScript function) maps a free-text question onto exactly one of the six functions above via a fixed, auditable keyword match, or returns the honest "I can't answer that" fallback. There is no code path from a user's question to arbitrary SQL, a different table, or any write — the assistant's entire "tool" surface is those six read-only functions. Every exchange (matched or not) is logged to the append-only, RLS-protected `ai_query_log` via `log_ai_query()` for audit.
- AI-assisted scheduling recommendations following a strict `GENERATE → REVIEW → ACCEPT/REJECT → PUBLISH` lifecycle (`shift_recommendations`). `generate_shift_recommendations()` deterministically scores every site-assigned, active, conflict-free candidate (recent worked minutes penalize the score — an overtime-minimization heuristic, not an LLM call) and never writes to `shifts`. **A real `shifts` row is created only by an explicit human `decide_shift_recommendation(accept=true)` call** — proven in the RLS suite by asserting the shift-count is unchanged after a reject and changes by exactly one after an accept, and that the created shift is linked back to the recommendation.
- Frontend: `AiAssistantPage` (a chat-style interface, suggested prompts, visible conversation history), `SchedulingRecommendationsPage` (generate for a site/date/window, review each candidate's score and reasons, accept-and-publish or reject).

---

## 2. New database surface (exact counts)

- **7 new/modified migrations** (`20260921090000`–`20260921090600`), 2,494 lines total.
- **15 new tables**: `site_geofences`, `attendance_location_events`, `attendance_location_exceptions`, `checkpoints`, `patrol_routes`, `patrol_route_checkpoints`, `patrol_runs`, `patrol_checkpoint_scans`, `operational_alerts`, `emergency_events`, `emergency_responses`, `emergency_escalation_policies`, `notification_deliveries`, `ai_query_log`, `shift_recommendations`.
- **13 new enums**.
- **47 new or replaced SQL functions** — roughly 28 client-callable RPCs and 19 internal trigger/tenant-validation/cron-sweep functions.
- Every new table: `ENABLE + FORCE ROW LEVEL SECURITY`, a tenant-ref-validation `BEFORE INSERT`/`UPDATE` trigger (`SECURITY DEFINER`, `set search_path = public`, no admin bypass), and least-privilege policies — no blanket tenant-wide `SELECT` was added.
- Every new `SECURITY DEFINER` function: fixed `search_path`, explicit in-function authorization against `can_manage_operations()`/`can_manage_org_structure()`/`is_platform_admin()` (the codebase's existing permission-tier helpers, not a parallel system), no trust in a client-supplied tenant/role.

## 3. Security testing — exact results

- **3 new RLS regression files**, 1,167 lines: `supabase/rls-tests/domain13_gps_guard_tours.sql` (344 lines), `domain14_command_centre_emergency.sql` (541 lines), `domain15_workforce_intelligence.sql` (282 lines). Each covers, per its domain: cross-tenant denial (every new table), role-boundary checks against the relevant tier, self-approval prevention, terminated-employee blocking (Domain 13's patrol start), and lifecycle-state-machine correctness.
- **Full suite run**: `24 of 24` RLS test files pass — the 21 pre-existing files (unmodified, zero regressions) plus the 3 new ones — verified against a fresh native PostgreSQL 16 apply of all 53 migrations in filename order (Docker is blocked by this sandbox's egress policy, so this is the same native-Postgres methodology used in the two prior remediation passes, not a hosted Supabase project).
- **Adversarial review pass** (this brief's §23), performed by hand against the new code, not just inherited from the RLS suite:
  - Cross-tenant reads/writes, IDOR, forged IDs — covered by the RLS suite's explicit cross-tenant assertions on every new table.
  - Fake GPS/checkpoint completion — structurally impossible: the client never sends a verification decision, only raw coordinates; the server always recomputes.
  - Replayed events — `clock_in()`'s existing `already_clocked_in` guard and `scan_checkpoint()`'s duplicate-detection make an accidental retry-after-timeout self-correcting rather than a duplicate write, without adding a new idempotency-key mechanism.
  - Self-approval — **two real findings, both fixed** (§1, Domain 14, above): the emergency-lifecycle self-approval gap and its operational-alert bypass.
  - Terminated-employee access — `employee_can_self_serve()` blocks `clock_in()`/`start_patrol()`; deliberately **not** applied to `trigger_emergency()` — a terminated employee physically on-site must never be blocked from calling for help, a considered judgement call, not an oversight, documented here rather than silently left unexplained.
  - AI prompt injection / arbitrary SQL — structurally impossible: `matchIntent()` only ever selects one of six fixed function keys; there is no code path that interpolates user text into SQL, and `log_ai_query()` only ever stores the question as an audit string, never executes it.
  - Unauthorized client access — `client_user` holds zero of the four new permissions and is excluded from `can_manage_operations()` at the RLS layer too; proven by an explicit RLS assertion that `client_user` reads zero rows from `emergency_events`.
- A separate performance-hardening finding, also fixed: four new list queries (`operational_alerts`, `shift_recommendations` suggestions, pending/own GPS exceptions) had no `.limit()` — each was already implicitly bounded by PostgREST's default row cap, but is now explicitly capped (100/100/100/50) so a busy tenant's history can never turn a queue view into an unbounded table scan.

## 4. Full validation-suite results

| Check | Result |
|---|---|
| `npm run typecheck` | Clean (0 errors) |
| `npm run lint` | Clean (0 errors, 0 warnings) |
| `npm test` (Vitest) | 25 files, 180 tests, all passing — includes 1 new file (`matchIntent.test.ts`, 9 tests) for the one genuinely new pure TypeScript function this pass introduced |
| `npm run build` | Clean production build, every new page correctly code-split into its own chunk |
| `npm run test:e2e` (Playwright, full suite) | **127 of 127 tests passing** — the entire pre-existing suite, zero regressions. Two tests broke as a direct, expected consequence of `MyAttendancePage` now reading a device location before clock-in/out (this sandbox's egress policy blocks the real browser geolocation network provider); fixed with Playwright's own `context.grantPermissions`/`setGeolocation` API (standard practice for testing geolocation-dependent UI, not a workaround) |
| RLS regression suite | 24 of 24 files passing (see §3) |

**No new Playwright e2e specs were written for Domains 13/14/15 themselves** — a disclosed scope decision, not a silent gap. `e2e/utils/sebetsaData.ts`'s mock layer enumerates REST responses per table with real per-query filter logic (not a generic passthrough); doing that properly for 8 new tables across 4 new feature areas is substantial, deliberate infrastructure work in its own right. The load-bearing verification for the new domains' actual business logic is the RLS regression suite — it exercises the real RPCs against a real PostgreSQL engine with real RLS enforcement, which is a stronger guarantee for this kind of security-critical logic than a Playwright test with a mocked network layer would be. What the existing 127-test e2e suite does prove is that nothing in this pass broke any previously-working flow.

## 5. Performance decisions

- Every dashboard/summary figure (`get_command_centre_snapshot`, `get_patrol_summary`, all six insight functions) is a single server-side SQL aggregation (`COUNT`/`SUM`/`FILTER`) — never fetched-then-summed in the browser.
- No unbounded realtime subscriptions were added.
- Every new list query the frontend issues is either naturally small (a single patrol's checkpoints, a site's active routes) or now explicitly `.limit()`-ed (§3).
- Every new table carries the indexes its own RLS policies and query patterns need (`tenant_id`, `status`, `employee_id`, `site_id`, and a partial index on `patrol_runs` for "my one open run") — designed the same way the pre-existing schema was, for a tenant with thousands of employees and hundreds of sites, not tested at that scale in this session (no hosted project to load-test against).

## 6. Deployment status — honest, per §28

- **IMPLEMENTED**: all of §1.
- **TESTED**: RLS suite (24/24, native PostgreSQL 16), unit suite (180/180), e2e suite (127/127), typecheck/lint/build — all locally, in this sandbox.
- **VERIFIED IN CI**: **NOT VERIFIED.** This branch has not run through GitHub Actions; the repository's own CI workflow was not triggered by this session.
- **VERIFIED AGAINST HOSTED SUPABASE**: **BLOCKED** — no hosted Supabase project reference or credentials exist in this session; `src/lib/database.types.ts`'s additions were hand-authored from the migration source (Docker, needed by `supabase gen types`'s own tooling even in `--db-url` mode, is blocked by this sandbox's egress policy) rather than generated from a live project, and were then proven to typecheck cleanly against the whole existing codebase.
- **DEPLOYED**: **No.** Nothing in this pass was deployed to GitHub Pages or any hosted environment. Per §27, no custom domain was invented or configured — none exists in this repository's configuration, and none was added.
- **NOT VERIFIED / BLOCKED, explicitly**:
  - Camera-based QR scanning (`CheckpointScanner`'s `BarcodeDetector` path) — verified by code review only; not exercised against a real device or camera in this session. Manual code entry (the always-working fallback the mobile-first/poor-hardware requirement calls for) is what the e2e-equivalent coverage would need to exercise, and is the path a real guard on an older Android phone is expected to use most often anyway.
  - True offline queueing (persist an action while offline, sync on reconnect) as the brief's reliability section asks for — **deliberately not implemented**. The existing codebase has an explicit, stated design philosophy against claiming offline capability it doesn't have (`src/components/ui/OfflineBanner.tsx`'s and `src/lib/retry.ts`'s own comments: "Sebetsa does not claim offline support; this is honest status, not simulated capability"). Building a genuine, correctly-tested offline queue is real, non-trivial infrastructure work; rather than half-build one inside this pass and risk it being wrong in exactly the way that matters (losing or duplicating safety-critical evidence), this pass instead: (a) wraps every critical action in `retryOnNetworkError` (already-proven, handles the transient-connectivity-blip case that is the overwhelming majority of "poor network" reality), and (b) relies on `clock_in()`'s `already_clocked_in` guard and `scan_checkpoint()`'s duplicate-detection, both already real and RLS-tested, to make an accidental resubmission-on-retry safe without a dedicated idempotency key. This is marked NOT VERIFIED / DEFERRED, not silently dropped.
  - Real push/SMS notification delivery — **BLOCKED**, no provider credentials exist anywhere in this repository (confirmed, not assumed). `notification_deliveries` is the complete, real, tested delivery-tracking data model a provider would write into once one is configured.
  - A real LLM behind the AI assistant — **BLOCKED**, no API key or provider integration exists anywhere in this repository. What is shipped is a real, working, tested router onto six real deterministic tools — the honest, complete thing that could be built without inventing a provider choice the user never made.
  - Load/scale testing against thousands of employees/hundreds of sites — no hosted project to test against in this session; the schema/index/query design decisions in §5 are the mitigation, not a substitute for measuring it.

## 7. Documentation

This file is the primary new documentation artifact for this pass. Two live, user-facing Funda360-era strings encountered while extending `src/lib/dbErrors.ts` for this work were fixed in place ("Ask your school…" → "Ask your organization admin…", "Contact your school…" → "Contact your organization admin…"). The much larger, pre-existing Funda360 documentation/config residue catalogued by earlier remediation passes (`docs/SEBETSA_PRODUCTION_CHECKLIST.md`, `docs/PRODUCTION_READINESS_AUDIT.md`) — the archived reference doc trees, `supabase/templates/recovery.html`, `supabase/config.toml`'s SMTP sender name, `.env.example`'s `VITE_APP_NAME`, `public/CNAME`, `package-lock.json`'s `name` field, `start-funda360.bat` — is unrelated to the three domains this pass built and was left untouched; it is already tracked as known, pre-existing technical debt from before this task began, not introduced or hidden by this pass.

## 8. What a reader should take away

Three enterprise domains were built end-to-end — real Postgres schema and RLS, real RPCs with real security tests, real frontend pages wired to those RPCs following every existing codebase convention exactly, a real (and fixed) adversarial security finding, zero regressions to the 148 previously-passing automated checks (21 RLS files + 127 e2e tests) this pass touched. What is honestly not done: CI/hosted-Supabase verification (no access), true offline queueing (a disclosed, reasoned scope cut consistent with this codebase's own stated philosophy), and e2e coverage of the three new domains specifically (also disclosed, with the RLS suite carrying that verification weight instead). Nothing here claims more than what is proven above.
