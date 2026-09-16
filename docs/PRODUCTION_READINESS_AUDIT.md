# Sebetsa — Enterprise Production Readiness & Forensic Audit

> **Remediation status (2026-09-15):** every CRITICAL finding and 5 of 7 HIGH findings below have since been fixed, migrated, and verified against a live database with a passing regression test. This document is preserved as the original point-in-time audit record and is **not** updated in place — see [`SEBETSA_REMEDIATION_REPORT.md`](./SEBETSA_REMEDIATION_REPORT.md) for exactly what changed, how it was verified, and the honest list of what was explicitly *not* fixed. Do not read this document's verdict below as the current state of the codebase.

**Audited:** 2026-09-15, repository `Jablo-cmd/sebetsa`, branch `main` @ commit `74b957f`
**Scope:** Full repository — 46 database migrations, 13 RLS test files, 3 Edge Functions, ~50 frontend feature modules, 54 E2E spec files, 171 unit tests, CI configuration, and documentation.
**Method:** Direct inspection (typecheck/lint/unit-test/build runs performed locally; GitHub Actions run history and job logs pulled directly) plus six parallel forensic passes over the database schema, multi-tenancy/RBAC/RPC security, business rules and cross-module integrity, application security/storage/edge functions, repository hygiene and documentation, and mobile/accessibility/performance/testing coverage. Every finding below is cited to a specific file and line. Companion documents: [`SEBETSA_MODULE_MATRIX.md`](./SEBETSA_MODULE_MATRIX.md) (per-module technical reference) and [`SEBETSA_PRODUCTION_CHECKLIST.md`](./SEBETSA_PRODUCTION_CHECKLIST.md) (actionable checklist).

---

## Executive Summary

Sebetsa is a genuinely substantial, largely well-engineered enterprise workforce platform. The database schema is disciplined — universal RLS with `FORCE`, consistent tenant-FK-validation triggers across almost every domain, real Postgres exclusion constraints preventing shift double-booking, a ledger-vs-snapshot leave-balance design, and DB-enforced state machines for nearly every lifecycle (leave, tasks, incidents, contracts, assets, procurement, compliance). The frontend is equally disciplined at the component level: no XSS sinks anywhere in the codebase, no secrets exposed to the browser, consistent loading/error/empty states, real destructive-action confirmation, and no stub or "Coming Soon" pages — every one of the 46 routes is a genuine, functional implementation.

That said, this audit found **two live, currently-exploitable cross-tenant security bugs**, **one critical business-logic failure that lets terminated employees retain full application access indefinitely**, and **a CI/CD pipeline that is red on `main` right now** across three of its five jobs, with the fourth (deploy) failing for an unrelated but equally blocking reason. Layered on top of that is a recurring architectural gap — self-approval is not blocked on the vast majority of "manager confirms an employee's own submission" workflows (leave, attendance corrections, task verification, compliance verification, incident-action verification, skill/qualification verification) — and a substantial amount of incompletely-removed Funda360 (the school-SaaS product this codebase evolved from) material, some of which is genuinely cosmetic (docs) but some of which reaches real, currently-shipped end-user-facing UI copy and two fully orphaned, dead-but-deployed Edge Functions.

**Verdict: NOT PRODUCTION READY, and not currently safe for even a controlled pilot with real tenant data.** The two cross-tenant RLS bugs and the terminated-employee-access gap are each small, well-scoped fixes (a policy rewrite and an RPC/RLS check, respectively) — this is not a "rebuild the architecture" situation, it is a "fix roughly eight specific, well-understood defects" situation. Once the P0 list in this report is closed, a tightly scoped pilot with a small number of trusted tenants is a reasonable next step, provided the pilot is monitored and the P1 list is actively being worked in parallel.

### Major strengths
- Universal, consistently-applied RLS (`ENABLE` + `FORCE` on all 60 tables, verified) with a well-reasoned `current_tenant_id()`/`is_platform_admin()` foundation that correctly avoids RLS self-recursion.
- Real, DB-enforced business constraints in several domains: shift double-booking prevention via a genuine Postgres `EXCLUDE` constraint, duplicate-clock-in prevention via a partial unique index, an audited leave-vs-schedule conflict guard, append-only ledgers for leave balances and inventory movements.
- A correct, working template for self-approval prevention already exists (`decide_procurement_request()`) — it just wasn't applied to the other five domains that need it.
- No XSS sinks, no committed secrets, no dynamic SQL, sound password-reset/session-invalidation behavior, and genuinely good document-storage security (server-generated paths, sanitized filenames, signed URLs) — the one exception (storage-layer sensitivity bypass) is narrow and specific, not systemic.
- Every route is a real, functional page — no placeholder/stub functionality anywhere in the 46-route surface.
- The one module with zero material integrity finding: Reporting/Analytics, whose `get_operational_metrics()` design (deliberate `SECURITY INVOKER`, riding existing per-table RLS) is both correct and confirmed correct by direct trace, not just by migration comment.

### Major weaknesses
- Two CRITICAL cross-tenant RLS bugs (§ Multi-Tenancy Findings).
- Terminated employees retain full self-service application access indefinitely (§ Business Rules).
- CI is red on `main`: the RLS regression suite has no runnable script and fails instantly; the Edge Function typecheck job fails on a file that doesn't exist; the E2E suite is 179/261 failing, with 74% of its spec files importing a legacy auth utility that silently fails to authenticate against the real app; the deploy job fails on missing secrets (§ Testing Coverage, § Production Blockers).
- Self-approval / separation-of-duties is missing across leave approval, attendance-correction approval, task verification, compliance verification, and incident-action verification — a systemic pattern, not five unrelated bugs (§ Business Rules, § RBAC).
- Two Edge Functions (`payments-initiate`, `payments-webhook`) and one (`notifications-dispatch`) are fully orphaned dead code referencing database tables that do not exist anywhere in the live schema — deployed-looking, still typechecked by CI, not merely "unwired" (§ Edge Functions).
- Real, live-user-facing Funda360 (school-SaaS) contamination beyond documentation: shipped error copy ("Contact your school for help"), login placeholders ("you@school.edu"), and a `docs/DOMAIN_STATUS.md` that actively instructs a future session to resume building removed school features (§ Documentation).

### Production readiness
- **Production: NOT READY.**
- **Controlled pilot: NOT READY YET**, specifically because of the two cross-tenant RLS bugs and the terminated-employee-access gap — these are unacceptable even in a small, trusted pilot with real employee PII. Once the P0 list below is closed (realistically small: a handful of migrations), a pilot becomes reasonable.
- **General rollout: blocked** on the full P0+P1 list, particularly restoring a working CI gate (RLS suite executable, E2E suite de-contaminated and filtered) before any of these fixes can be trusted not to regress silently.

---

## Capability Matrix

See [`SEBETSA_MODULE_MATRIX.md`](./SEBETSA_MODULE_MATRIX.md) for the full per-module table (routes, tables, RPCs, roles, RLS, tests, known gaps, status). Summary:

| Module | Implemented | Tested (meaningfully, currently) | Production-ready |
|---|---|---|---|
| Auth & Identity | Full | No (MFA/session flows: 0 proven E2E, 0 RLS, 0 unit) | 🟡 core flow sound, MFA enforcement gap |
| Multi-Tenancy / Organizations | Full | Partial (RLS file exists, never runs) | 🔴 two CRITICAL RLS bugs |
| People (Employees/Teams/Users) | Full | Thin | 🔴 terminated-employee-access CRITICAL |
| Site Operations | Full | Thin | 🔴 no business-rule enforcement |
| Scheduling | Full | Good unit, zero E2E | 🟡 strong DB constraints, missing cross-domain checks |
| Attendance | Full | Good | 🟡 same terminated-employee root cause |
| Leave | Full | Good | 🟡 best-designed domain, self-approval + balance gaps |
| Tasks | Full | Thin | 🟡 self-verification gap |
| Documents | Full | Thin | 🟡 storage-layer sensitivity bypass |
| Compliance & Incidents | Full | Thinnest E2E in the app | 🔴 false "cannot self-verify" claim, dead expiry sweep |
| Assets/Inventory/Procurement | Full | Thin | 🟡 Procurement is best-in-class; Assets missing tenant trigger |
| Workforce Development | Full | Thin | 🟡 privacy boundary correct; expiry has no operational effect |
| Reporting/Analytics | Full | Thin | 🟢 confirmed sound |
| Notifications | Full (in-app) | None (no RLS file exists) | 🟡 in-app clean; delivery worker is dead code |
| Payments | Backend only, dormant | N/A | ⚫ orphaned, references nonexistent schema |

---

## Security Findings

### CRITICAL

**C-1. `employees_write_by_manager` RLS policy allows any `hr_user`, in any tenant, to read, write, and delete every tenant's entire `employees` table.**
`supabase/migrations/20260911100600_employees_and_teams.sql:164-166`:
```sql
create policy employees_write_by_manager on public.employees for all to authenticated
  using (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user')
  with check (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user');
```
Every other write-tier helper in this codebase binds its role check to the row's own tenant. This one's second OR-branch checks only `role = 'hr_user'`, with no tenant comparison at all. Because this is a single `FOR ALL` policy, the predicate governs SELECT-during-UPDATE/DELETE visibility, INSERT, UPDATE, and DELETE uniformly. A statically-traced, unambiguous attack: an `hr_user` account in Tenant A can execute `UPDATE public.employees SET first_name = first_name RETURNING *;` with no `WHERE` clause and receive every employee row for every tenant in the system in one query (RETURNING visibility is governed by the UPDATE policy, not the separate SELECT policy). The same account can execute `DELETE FROM public.employees;` and delete the entire table, system-wide. This predates and was not caught by the earlier "pre-Phase-H RPC grants" hardening pass — it is an RLS policy bug, not a grants bug.

**C-2. Twelve-plus tenant-scoped tables have a blanket "any authenticated tenant member" SELECT policy with no role check**, letting the zero-permission `client_user` role and the low-privilege `employee` role read data the application's own permission catalogue says they should never see. Affected tables (all `tenant_id = current_tenant_id() or is_platform_admin()` with no additional role predicate): `employees` (full PII: name, email, phone, employment status, supervisor), `teams`, `team_members`, `site_assignments`, `regions`, `clients`, `sites`, `contracts` (contract numbers, SLA notes), `contract_sites`, `departments`, `positions`, `shifts` (full company-wide schedule), `shift_substitutions`, `shift_definitions`, `site_staffing_requirements`, and `profiles` (every user's name/email/phone/status in the tenant). File locations: `20260911100600_employees_and_teams.sql:162-179`, `20260911100500_org_hierarchy.sql:51-186`, `20260911101000_scheduling_and_attendance.sql:140-146`, `20260911101700_scheduling_and_availability.sql:58`, `20260913100000_workforce_site_operations.sql:62`, `20260911100200_row_level_security_base.sql:53-61`. This is a confirmed, direct match for the audit brief's specific concern about `client_user` reaching internal HR data: `client_user` appears exactly once in the entire codebase (the enum definition) and is otherwise correctly denied everywhere a narrower helper is used — but these tables never received that narrowing, unlike `leave_requests` and `attendance_records`, which were explicitly hardened from this same over-broad shape earlier in the project's history (the fix pattern is proven and precedented; it just wasn't applied here).

**C-3. Terminated employees retain full application access indefinitely.** `terminate_employee()` (`supabase/migrations/20260911100700_audit_log.sql:116-156`) sets `employees.employment_status='terminated'` and `profiles.status='inactive'`, but `profiles.status` is never read by any RLS policy or RPC anywhere in the 46 migrations (confirmed by exhaustive grep — the only references are the two writes inside `terminate_employee`/`reactivate_employee` themselves). `employees.profile_id` is also never nulled. Consequence: the employee's Supabase Auth session/JWT stays fully valid, and every self-service RPC that checks `e.profile_id = auth.uid()` — `clock_in`, `submit_leave_request`, `request_attendance_correction`, `complete_task`, availability writes — continues to succeed after termination. For a workforce/security-staffing platform, this is a core control failure: a dismissed guard or cleaner keeps full system access, including clocking in (with associated pay implications) and submitting leave, until someone manually revokes their Supabase Auth credentials out-of-band.

**C-4. CI is currently red on `main`.** Verified directly against GitHub Actions run history on the exact commit this codebase is built from (`74b957f`): the "Typecheck, lint, unit tests, build" job passes; the "Playwright end-to-end suite" job fails (179 failed / 82 passed); the "Edge Function (Deno) tests" job fails at the typecheck step (`TS2307: Cannot find module '.../admissions-public/index.ts'` — a file that doesn't exist in this repo); the "RLS / trigger / SECURITY DEFINER regression suite" job fails in under a second (`supabase/rls-tests/run.sh: No such file or directory`, exit 127); and the "Deploy to GitHub Pages" job fails on missing `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` secrets. There is currently no functioning, green path from a commit on `main` to a verified, deployed build. This is "production build/deployment failure" per the audit's own severity rubric.

**C-5. `site_assignments` has effectively no server-side business-rule enforcement**, and — combined with C-3 — the compounding effect is severe: no overlap/exclusion constraint (an employee can hold two simultaneous open site assignments), no check that the target site is `active`, **no check that the employee is `active`** (a terminated employee can be freshly assigned to a site), and no contract-validity gate at all (an assignment can be created against a `terminated`/`expired` contract, or a site with no contract). There is no RPC for this domain — the frontend performs a raw `supabase.from('site_assignments').insert()` (`src/features/siteAssignments/services/siteAssignmentService.ts:47-62`), and the only trigger present, `validate_site_assignment_tenant_refs()` (`supabase/migrations/20260911101600_workforce_management.sql:150-170`), checks only tenant membership. Stacked with C-3, a terminated employee can be actively scheduled, assigned to a client site, and clock in there — a security-staffing company's worst-case operational-integrity scenario, reachable through the ordinary UI with zero rejection at any layer.

### HIGH

- **Self-approval / separation-of-duties is missing across five of six "manager decides on someone's own submission" RPCs.** `decide_procurement_request()` (`supabase/migrations/20260915090100_procurement_inventory_asset_rpcs.sql:303-305`) correctly checks `if v_requested_by = auth.uid() and not is_platform_admin() then raise exception ...` — proving the team knows this pattern. It is missing from `approve_leave_request`/`reject_leave_request`/`revoke_leave_request` (`leave_rpcs.sql:167-336`), `decide_attendance_correction` (`attendance_rpcs.sql:352-408`), `verify_task` (`task_rpcs.sql:69-97`), `verify_compliance_record` (`compliance_incident_rpcs.sql:374-412` — **whose own migration comment falsely claims this is already blocked**: "the responsible person can move it to 'in_progress'/attach evidence, but cannot self-verify their own compliance," `compliance_safety_incidents.sql:295-297`), `verify_incident_action` (`compliance_incident_rpcs.sql:251-290`), and `verify_employee_qualification`/`verify_employee_skill` (`workforce_performance_training_skills_rpcs.sql:51-79,143-175`). Because the approving/verifying roles in every one of these domains overlap with roles that also hold the underlying employee record (an `organization_administrator`, `hr_user`, `regional_manager`, or `site_manager` is themselves an `employees` row), a single privileged account can submit-then-approve or complete-then-verify its own work in each of these six domains.
- **MFA for "required" roles is enforced only as a dismissible UI banner.** `src/features/rbac/constants/mfaRequiredRoles.ts:11-13` self-documents this: *"'Required' here is a soft requirement enforced in the UI... not yet a hard block."* No RLS policy or RPC anywhere checks `auth.jwt()->>'aal'` (confirmed by grep — zero matches across all 46 migrations). A compromised password for a `platform_administrator`/`organization_administrator`/`hr_user` account faces no MFA barrier unless that account happened to voluntarily enroll.
- **`storage.objects` RLS for the `employee-documents` bucket does not replicate the medical/disciplinary sensitivity split the metadata table enforces**, letting `operations_manager` (explicitly excluded at the metadata layer, `20260913120000_employee_documents.sql:87-101`) bypass it by calling the Storage API directly (`employee_documents_storage_select`, same file `:126-139`). The migration's own comment acknowledges this and relies entirely on "the frontend never requests a signed URL for a document the metadata query didn't return" — a trust-the-client assumption inconsistent with the rest of this migration set's own design philosophy.
- **`payments-initiate`, `payments-webhook`, and `notifications-dispatch` are fully orphaned dead code**, referencing `payment_intents`, `payment_gateway_configs`, `learners`, `settle_payment_intent`, and `notification_deliveries` — none of which exist anywhere in the 46 live Sebetsa migrations (only in the archived `docs/funda360-reference-migrations/`). `payments-initiate` still literally uses Funda360's schema shape (`school_id`, a `learners` table, `"School fees — {learnerName}"` line-item text, `supabase/functions/payments-initiate/index.ts:71`). Any invocation today fails at the first database call — not currently exploitable — but these are deployed-looking, CI-typechecked functions, not clearly-marked-dormant code, and independent of dormancy they carry three real defects that would ship live on day one if someone "finished" them without reading this audit: `payments-initiate` leaks raw exception text to callers (`index.ts:85`); the entire settlement safety net (signature-gate enforcement, amount re-verification, idempotency) exists only in code comments referencing an RPC that was never written; and CORS is wildcarded on the one function meant to be browser-invoked. The 5 payment-provider signature-verification adapters themselves (`_shared/providers/*.ts`) are genuinely well-implemented, constant-time, non-trivial code — the engineering quality is real, just unreachable.
- **Org-hierarchy tables (`clients`, `sites`, `contracts`, `contract_sites`) never received the cross-tenant FK-validation trigger every other domain in this codebase has.** Confirmed via grep — zero `validate_client_tenant_ref`/`validate_site_tenant_ref`/`validate_contract_tenant_ref`-style triggers exist, unlike employees/teams/shifts/tasks/compliance/assets/training, all of which do. A `clients.region_id`, `sites.client_id`, or `contracts.client_id` can be set to a UUID belonging to a different tenant with no rejection — an "impossible state" reachable by ordinary legitimate write access, not merely an RLS bypass, and untested by `supabase/rls-tests/org_hierarchy.sql` (which only tests direct tenant-column forgery, not this cross-reference case).
- **`asset_assignments` has no cross-tenant validation trigger at all** — the one relationship table in the entire schema missing this treatment (every other domain got it). `assign_asset()` (`procurement_inventory_asset_rpcs.sql:12-64`) accepts employee/team/site IDs with zero check they belong to the asset's own tenant.
- **`organizations` cascade-deletes the entire tenant graph** — including `audit_log`, `incidents`, and `compliance_records` — with no soft-delete or retention path (`20260911100000_create_organizations.sql` and ~30 downstream `ON DELETE CASCADE` FKs). Not currently reachable (no RPC exposes organization deletion), but a landmine for whoever adds that feature later, and specifically dangerous for the "append-only, tamper-resistant" tables whose entire design intent is durability.
- **`approve_leave_request()` never checks the request against `leave_balances.remaining`** before approving (`leave_rpcs.sql:191-210`) — a request can be approved that drives the balance negative.
- **Compliance-record expiry is fully implemented but never invoked.** `sync_expired_compliance_records()` (`compliance_incident_rpcs.sql:422-460`) correctly flips expired records' status and notifies the responsible person — but is never called from the frontend (confirmed by grep — it appears only in generated TypeScript types). A `compliant` record past its `expiry_date` displays as compliant indefinitely.
- **Required-certification expiry has zero operational effect.** `training_requirements` (a catalogue of what's required per role/site) is never joined against `shifts` anywhere — an employee with an expired required certification can still be freely scheduled into a role/site that requires it.
- **Contract status never auto-transitions on time, and no downstream domain checks it.** Nothing flips an `active` contract to `expiring`/`expired` based on `end_date`, and `site_assignments`/`shifts`/`tasks` never check `contracts.status` or `contract_sites` at all — a site can continue full operations under a terminated/expired contract with zero friction.
- **74% of the E2E suite (40/54 spec files) imports a legacy auth-mocking utility that silently fails to authenticate against the real app** — `e2e/utils/mockAuth.ts` seeds `localStorage` under the key `'funda360-auth'`, but the real app's Supabase client uses `'sebetsa-auth'` (`src/lib/supabase.ts:13,46`); this mismatch is documented in the codebase's own newer utility (`e2e/utils/sebetsaAuth.ts:4-10`). Affected files include several whose names sound like core, currently-verified coverage: `employees.spec.ts`, `users.spec.ts`, `login.spec.ts`, `notifications.spec.ts`, `tenant.spec.ts`, `mfa.spec.ts`, `accessibility.spec.ts`, `ui-primitives.spec.ts`. The commit history's own "X/Y Sebetsa-native E2E passing" claims are not reproducible against this CI configuration.
- **The shared `Modal` component never returns focus to the triggering element on close** (`src/components/ui/Modal.tsx:19-56`) — a real WAI-ARIA dialog-pattern regression across nearly every create/edit/destructive-action workflow in the app, since `Modal` is the shared primitive for essentially all of them.
- **At least 6 Funda360-branded strings are still shown to real end users**, beyond the previously-known `dbErrors.ts` instance: `src/features/users/pages/UsersPage.tsx:36` ("Manage the staff accounts at your school"), `UserProfilePage.tsx:91` ("School association" field label), `LoginForm.tsx:86`/`ForgotPasswordForm.tsx:75` (placeholder `you@school.edu`), `MfaChallengePage.tsx:74` ("Contact your school administrator"), `NotificationSettingsPage.tsx:88` ("if your school has enabled it").
- **`docs/DOMAIN_STATUS.md` self-labels as "the authoritative roadmap... for the remaining Funda360 development sequence"** and instructs a future session to resume implementing Funda360 domains (Finance, Report Cards, Homework, Parent Portal, etc.). This is actively misleading operational documentation, not passive noise — if followed, it would steer future work backward into rebuilding removed school features.

### MEDIUM (representative — full list in the checklist)
`submit_leave_request()`'s missing upsert pattern (silently drops the first-ever pending-balance record for an employee/type/year); `create_contract_document_slot()`'s missing filename sanitization (its sibling function has it); `compute_sla_measurement()` unconditionally rejecting the schema-supported contract-wide-SLA case; `profiles.tenant_id ON DELETE SET NULL` vs. every other table's `CASCADE` (inconsistent tenant-deletion story); the unaddressed structural twin of the (already-fixed-once) function-grants issue on the boolean `can_manage_*` helper functions; no overlapping-leave-request prevention; task assignment/reassignment crossing site boundaries unchecked; a direct-write escape hatch (`attendance_records_write_by_manager`) around the two-party attendance-correction workflow; no future-date validation on attendance corrections; no cross-site check on asset assignment; incidents lacking an HR-sensitivity visibility split analogous to documents; no magic-byte content-sniffing on document uploads (self-acknowledged, deferred); `AttendancePage.tsx`'s `todayIsoDate()` using `.toISOString()` (UTC) rather than SAST-local, causing an off-by-one-day window around midnight; no shared date-formatting utility (8+ files format dates independently, inconsistent locale handling); platform-admin cross-tenant reads generating no audit trail; 2 moderate + 2 low `npm audit` findings (`react-router-dom` open-redirect/constructor-injection CVEs; `@supabase/auth-js` path-routing CVE via an unusually old, exact-pinned `supabase-js@2.45.4`); package-lock.json's `name` field drifted to `"funda360"`.

### LOW
`teams_select_within_tenant`'s same unscoped-by-permission shape (lower sensitivity than employees); session JWT in localStorage/sessionStorage (standard supabase-js SPA pattern, not itself a bug given no XSS sink exists); `get_operational_metrics()` returning misleading single-row aggregates for non-manager callers instead of erroring (by design, but a UX trap); CORS wildcard on `payments-initiate` (moot while dormant); `Checkbox` hit target at 16×16px; header/drawer/notification touch targets at 32–36px rather than 44px; misleadingly-auto-named `types-*.js` bundle chunk (it's Zod, not unerased TypeScript types — a real chunk-naming problem, not a real dead-code problem); three inconsistent evidence-attachment shapes across compliance/tasks/documents; `employees.home_site_id`/`site_assignments`/`shifts.site_id` triple redundancy with no documented reconciliation; RequirePermission's silent redirect-with-no-explanation UX.

---

## Multi-Tenancy Findings

Tenant isolation is **not currently sound**, evidenced directly (not inferred):

- **Attack B/C/D (cross-tenant insert/update/delete) SUCCEED against `employees`** via C-1 above — a policy bug, statically traced and unambiguous.
- **Attack A (cross-tenant read) SUCCEEDS cross-*role*** (not cross-tenant, but equally serious) for the 12+ tables in C-2 — any tenant member, including the zero-permission `client_user`, reads data no permission grants them.
- **Attack E (RPC tenant-bypass) is correctly DENIED everywhere sampled** — every mutating RPC checked (`adjust_leave_balance`, `provision_employee_login`, `terminate_employee`/`reactivate_employee`, and ~15 others read in full) derives `tenant_id` server-side from a row lookup rather than trusting a client-supplied value.
- **Attack G (cross-tenant storage access) is correctly DENIED** for all three buckets checked (`employee-documents`, `contract-documents`, `compliance-evidence`) — storage paths are server-generated, never client-chosen, and the RLS policies correctly compare the caller's own tenant against the path's tenant segment.
- **Attack F (ID enumeration) is moot for the 12+ tables in C-2** by construction (any in-tenant ID is already enumerable regardless of role), and was not exhaustively traced route-by-route for the tables where SELECT is correctly scoped, given audit time constraints.
- Cross-tenant FK-forgery protection (a legitimate write attempting to reference another tenant's child record) is comprehensively applied via ~30 `validate_*_tenant_refs()` triggers across most domains — the org-hierarchy tables (clients/sites/contracts) and `asset_assignments` are the two confirmed exceptions (HIGH findings above).
- All 60 tables carry both `ENABLE ROW LEVEL SECURITY` and `FORCE ROW LEVEL SECURITY` — there is no table silently relying on `auto_expose_new_tables=true` for baseline protection; the problem is specific broken/missing policies, not systemic absence of RLS.
- Platform-administrator cross-tenant access is a deliberate, necessary bypass (`is_platform_admin()`), correctly gated on the JWT role claim — but generates **no audit trail for reads**, only for mutating RPCs that explicitly call `write_audit_log()`.

**This static verification (SQL trace, no live database access) should be followed by a live penetration test against a real Supabase project once C-1 and C-2 are fixed**, to confirm the fixes and rule out anything this trace-based method could have missed.

---

## RBAC Matrix

9 roles, ranked: `platform_administrator`(100) > `organization_administrator`(90) > `operations_manager`(80) > `regional_manager`(70) > `site_manager`(60) > `supervisor`(50)/`hr_user`(45) > `employee`(30) > `client_user`(20). ~24 permission domains × `.view`/`.manage`/`.approve`.

- The frontend `RequirePermission` route guard is internally consistent with `rolePermissions.ts` — no orphaned permissions, no permanently-inaccessible routes (verified by cross-checking all 46 routes).
- The **real** access boundary (RLS) currently disagrees with the frontend's intent in two confirmed places (C-1, C-2) — `client_user` and plain `employee` can read data the permission catalogue says they shouldn't, and `hr_user` can write cross-tenant.
- Self-service boundaries are correctly narrow where implemented deliberately (e.g., `profiles` self-update is column-scoped via GRANT + two BEFORE UPDATE triggers preventing direct role/tenant self-escalation — a well-reasoned, carried-forward fix for a real vulnerability class).
- **Approval separation is the weakest part of the RBAC story**: as detailed above, 5 of 6 approval/verification RPCs don't check the approver differs from the subject. This is a role-tier problem overlapping with an identity problem — a role check alone is insufficient when the approving role and the submitting-employee identity can be the same person.
- Client access: `client_user` is correctly given zero explicit permissions in the frontend catalogue, but (per C-2) currently inherits broad backend read access it was never intended to have — the frontend's caution is not backed by the database.
- Platform-administrator cross-org access is real, necessary, and role-gated, but unaudited on the read side (noted above).

---

## Business Rules

Full domain-by-domain detail is in the module matrix. Headline pattern: **the database's status-transition and structural integrity is strong across nearly every domain** (leave, tasks, incidents, contracts, assets, procurement, compliance all have genuine DB-enforced state machines, not merely RPC-layer discipline) — but **cross-domain consequence** is frequently missing: an employee's termination doesn't affect anything else in the system; a certification's expiry doesn't affect scheduling; a contract's expiry doesn't affect site operations; an approved leave doesn't block a contradictory clock-in. Each domain in isolation is often solid; the connective tissue between domains — precisely what the audit brief calls "cross-module integrity" — is the recurring weak point, alongside the self-approval gap already covered under Security Findings.

Verified working, worth crediting explicitly: the leave↔scheduling conflict guard (blocks new shifts during approved leave, with an audited, permissioned override — the single strongest cross-module control in the codebase); the leave↔attendance sync (one-directional but correct as far as it goes); the training/skills HR-privacy boundary (confirmed to match its own documentation, unlike the compliance-verification claim which does not); consistent `timestamptz` usage for every instant-in-time column with no naive/local timestamp columns found anywhere in scheduling/attendance/leave.

---

## Database Findings

46/46 migrations read in full. Schema integrity is generally strong: consistent naming conventions across the entire history, tenant_id always the first FK column, uniform trigger-naming, and a genuinely comprehensive RLS baseline. Concrete integrity gaps: `organizations`'s cascade-delete blast radius (HIGH, above); the missing cross-tenant FK-validation triggers on org-hierarchy and `asset_assignments` (HIGH, above); `site_assignments`'s complete lack of overlap/status/contract constraints (CRITICAL, above); `submit_leave_request()`'s missing upsert (MEDIUM); and a handful of smaller inconsistencies (evidence-attachment modeled three different ways across compliance/tasks/documents; `site_id` triple-redundancy across employees/site_assignments/shifts with no documented reconciliation story). The 13 RLS test files themselves are genuinely thorough, specific, executable assertions — not superficial smoke tests — their only defect is that none of them currently run in CI (see Testing Coverage), and that a couple (`compliance_incidents.sql`'s self-verification section) assert the wrong scenario relative to what they claim to test.

---

## RPC Security

Approximately 60+ `SECURITY DEFINER` functions were surveyed; roughly 15 were read in full, the remainder confirmed via systematic grant/revoke tracing. Findings:

- The historical "implicit anon/authenticated EXECUTE grant" vulnerability class (fixed once mid-project for `write_audit_log`/`create_notification`/`seed_default_leave_types`, then found again and fixed retroactively for 5 pre-Phase-H RPCs in `20260918090100_security_hardening_pre_h_rpc_grants.sql`) is now **comprehensively closed for data-mutating/data-returning RPCs** — every function created from Phase H onward correctly revokes from `public, anon` immediately after creation. Its recurrence twice indicates this was never caught by an automated lint until a dedicated audit pass — nothing in CI would currently catch a new function forgetting this.
- **However, the boolean permission-helper functions themselves were never given the same explicit revoke** (`can_manage_profiles`, `can_assign_role`, `can_manage_org_structure`, `can_manage_operations`, `can_manage_employees`, `can_manage_leave`, `can_approve_leave`, `can_view_leave_broad`) — MEDIUM, low actual risk since they only return a boolean derived from `auth.uid()`/`auth.jwt()` (null/empty for `anon`), but the same gap-class the project explicitly says it closed.
- `get_operational_metrics()` is confirmed to be the sole, deliberate `SECURITY INVOKER` exception, and confirmed safe by trace (every subquery is tenant-filtered and additionally protected by the underlying table's own RLS).
- No SECURITY DEFINER function was found missing an explicit `search_path` where one was checked; no case of a client-supplied tenant_id being trusted for authorization was found in any RPC sampled.
- The systemic self-approval gap (Security Findings, above) is fundamentally an RPC-authorization-logic issue, not a grants issue — every affected function's grants are correct; the missing check is a business-logic predicate.

---

## Storage Security

`employee-documents`, `contract-documents`, and `compliance-evidence` buckets are all private, with server-generated, sanitized paths and time-limited (5-minute) signed URLs for downloads — no permanently-public URLs found anywhere. Cross-tenant access is correctly denied (Attack G, above). The one confirmed defect is the medical/disciplinary sensitivity-tier bypass on `employee-documents` (HIGH, above) — a documented, intentional restriction at the metadata layer that the storage layer doesn't replicate. Content-type validation is MIME/size-only (both client and server-side, genuinely layered) with no magic-byte sniffing — a self-acknowledged, honestly-documented deferred gap rather than an overclaimed one.

---

## Edge Functions

| Function | Auth | Status |
|---|---|---|
| `notifications-dispatch` | Fail-closed on a missing/mismatched dispatch secret (correct) | ⚫ Dead — queries a `notification_deliveries` table that doesn't exist in the live schema |
| `payments-initiate` | Requires a bearer JWT, RLS-scoped read (correct pattern) | ⚫ Dead — references `payment_intents`/`learners`/`school_id`, none of which exist; also leaks raw exception text (HIGH) |
| `payments-webhook` | Correctly unauthenticated by design (provider webhooks); real, good-quality constant-time signature verification for all 5 providers | ⚫ Dead — the described settlement safety net (`settle_payment_intent`) was never written; CORS wildcarded |

None of these are wired to any frontend route. All three are still `deno check`-ed by CI (`admissions-public`, also referenced there, doesn't exist in this repo at all — separate from the above three, and the direct cause of the Edge Function CI job's failure). **Recommendation: treat all three as either "finish or remove," not "leave as-is,"** since a deployed Edge Function is a publicly-invocable URL independent of frontend wiring, and their current state (dead-but-deployed, missing safety logic in comments-only form) is worse than either finishing them properly or removing them.

---

## Testing Coverage

The honest picture, not the count of files that exist:

| Layer | What exists | What it currently proves |
|---|---|---|
| Unit (vitest) | 171 tests, 24 files, all passing | Pure schema/utility-level logic only (zod schemas, date/money/pagination helpers, RBAC pure functions). Zero component or integration tests. |
| RLS (`supabase/rls-tests/*.sql`) | 13 genuinely thorough files (largest: `leave.sql`, 661 lines) | **Nothing currently** — the referenced `run.sh` doesn't exist in the live path (only archived under `docs/funda360-reference-other/`); CI's RLS job fails in under a second. |
| E2E (Playwright) | 54 spec files | 14 (26%) use the correct auth utility and target real routes; 40 (74%) import a legacy utility with a wrong storage key that silently fails to authenticate. The full unfiltered suite's last CI run: **179 failed / 82 passed**, including failures in files with entirely plausible Sebetsa names (`users.spec.ts`, `tenant.spec.ts`, `verify-email.spec.ts`). Even the 14 genuine files are not provably passing in isolation given the current CI configuration. |

The single highest-stakes property for a multi-tenant platform — tenant isolation — currently has **zero running proof of correctness**: the RLS suite that would test it doesn't execute, and the E2E spec that names it (`tenant.spec.ts`) doesn't authenticate against the real app. `notifications` has no RLS test file at all despite the service layer's own code comment naming RLS as its actual enforcement mechanism. This matters independently of whether the underlying code is correct (in several cases it is, per this audit's own manual trace) — a test that never runs proves nothing about current production behavior, and this audit's own findings (C-1, C-2) show that manual review alone is not sufficient either.

---

## Performance

No systemic issues found. No N+1 query patterns anywhere sampled. List pages use real server-side `.range()` pagination; report-scale aggregation correctly pages through PostgREST's 1000-row cap via a documented helper (`src/lib/pagination.ts`). Reporting confirmed to call the RPC directly with no client-side re-aggregation (disproving an initial hypothesis). The one bundle-size question raised (an 84KB auto-named `types-*.js` chunk) resolved to being the Zod validation library, not unerased TypeScript types — legitimate, shared, runtime-necessary code; the actual issue is just a misleading auto-generated chunk name that should be fixed via an explicit `manualChunks` entry so it doesn't mislead future investigations the way it did this one.

---

## Mobile / UX

Field-worker-facing pages (`MyAttendancePage`, `MySchedulePage`) are genuinely mobile-first: single-column, full-width 44px buttons, offline/error states surfaced, no tables at all. `Modal` correctly constrains to the viewport and scrolls internally — it cannot overflow off-screen on a phone. Admin-heavy tables (Employees, Users, Assets) use horizontal scroll rather than a card-collapse pattern, mitigated by a genuinely well-built scroll-affordance component (edge-fade shadows that only appear when there's more to scroll to). Concrete gaps: several header/navigation touch targets (menu trigger, drawer close, theme toggle, notification bell) sit at 32-36px rather than the 44px mobile guideline (they do clear the 24px WCAG floor); the `Checkbox` component's hit target is 16×16px; date formatting is ad-hoc across at least 8 files with no shared utility, risking visible inconsistency and contributing to one confirmed timezone bug (`AttendancePage.tsx`'s "today" helper uses UTC rather than SAST, producing a roughly two-hour nightly window where the default attendance-roster date is wrong). The one real accessibility defect of note: `Modal` never returns focus to its trigger on close, a WAI-ARIA regression affecting nearly every workflow in the app. WCAG AA color-contrast fixes claimed in prior commits were independently re-derived from the actual CSS token values and confirmed genuine, not aspirational.

---

## Documentation

`docs/` is dominated by Funda360 (the school-SaaS predecessor product) material: the 15 "FUNDA360 ACRONYM SPECIFICATION" documents open with literal LLM role-play generation prompts rather than real content; `docs/funda360-reference-migrations/` (76 files) and `docs/funda360-reference-other/` (the RLS test harness this project's own `run.sh` is missing, plus load-tests and a seed file) together account for roughly 68% of `docs/`'s total size and sit inside the primary documentation tree rather than clearly out-of-band. Some Funda360-era docs (`PAYMENT_GATEWAY.md`, `COMMUNICATION.md`, `NOTIFICATIONS_DELIVERY.md`) accurately describe what the corresponding (now-confirmed-orphaned) Edge Functions' code still does — salvage value is conceptual, not directly reusable, since the schema they describe was never ported. `docs/DOMAIN_STATUS.md` is the most concerning single file: it explicitly instructs a future session to resume Funda360 development, which is actively misleading rather than passively stale. **There is currently no Sebetsa-native architecture or domain-status document at all.** Contamination also reaches live source beyond docs: `.env.example`, `src/lib/dbErrors.ts` (dead-but-shipped error copy), and at least 6 real user-facing UI strings (Security Findings, above).

---

## Production Blockers

1. Cross-tenant RLS bug in `employees_write_by_manager` (C-1)
2. Blanket-SELECT policies on 12+ tables exposing internal data to under-privileged roles (C-2)
3. Terminated employees retain full application access (C-3)
4. CI is red on `main` across e2e, edge-functions, and rls-tests jobs, and the deploy job fails on missing secrets (C-4)
5. `site_assignments` has no server-side business-rule enforcement (C-5)

---

## Recommended Remediation Plan

**P0 — Must fix before production (and before any pilot):**
- Fix `employees_write_by_manager` (add the missing tenant comparison to the `hr_user` branch)
- Fix the 12+ blanket-SELECT policies to actually check role
- Make employee termination actually revoke self-service access (check `profiles.status`/`employment_status` in every self-service RPC, or deny at the session layer)
- Add basic `site_assignments` enforcement (employee/site active-status check, at minimum)
- Fix the RLS test runner (`run.sh`) so the 13 existing test files execute, and wire that job as a required CI check
- Remove the `admissions-public` reference from CI's Edge Function typecheck step
- Filter or remove the ~40 E2E specs using the broken legacy auth utility so CI's E2E job reflects real status
- Configure the missing GitHub Pages deploy secrets (or remove that job if deployment happens elsewhere)

**P1 — Must fix before pilot/general rollout:**
- Add self-approval guards to the five affected RPCs (leave, attendance correction, task verification, compliance verification, incident-action verification), using `decide_procurement_request()` as the template
- Add the missing cross-tenant FK-validation triggers (org-hierarchy tables, `asset_assignments`)
- Decide and implement a tenant-deletion story before any admin "delete organization" feature is ever built
- Fix the storage-layer medical/disciplinary sensitivity bypass
- Decide the fate of the three orphaned Edge Functions (finish or remove — not leave as-is)
- Wire `sync_expired_compliance_records()` into the frontend
- Add a leave-balance check to `approve_leave_request()`
- Fix `submit_leave_request()`'s missing upsert
- Decide whether MFA should become a hard requirement for privileged roles

**P2 — Important improvements before broad commercial deployment:**
- Decide whether expired certifications and expired/terminated contracts should gate scheduling/site-operations
- Add overlap prevention to `site_assignments`; add site-assignment checks to shift creation and clock-in
- Add a shared date-formatting utility; fix the UTC/SAST off-by-one in `AttendancePage.tsx`
- Fix `Modal`'s focus-return behavior
- Rewrite `.env.example`; remove the remaining user-facing Funda360 strings; replace `docs/DOMAIN_STATUS.md`
- Address the `npm audit` findings
- Move the Funda360 reference material out of the primary `docs/` tree

**P3 — Future optimization:**
- Card-collapse responsive pattern for admin-heavy tables
- Enlarge sub-44px touch targets
- Rename the misleading `types-*.js` bundle chunk
- Write a genuine Sebetsa-native architecture document
- General dependency freshness (React 19, Vite 8, etc. — normal drift, not urgent)

---

## Final Verdict

**NOT READY / [ ] PILOT READY / [ ] PRODUCTION READY** — Sebetsa is **NOT READY**, including for a controlled pilot with real tenant data, because of two live cross-tenant RLS bugs and a confirmed gap that lets terminated employees keep full system access indefinitely. None of these require an architectural rewrite — each is a targeted, well-understood fix (a handful of migrations plus wiring the existing, well-written RLS test suite into CI so regressions on these specific points are caught automatically going forward). Once the P0 list above is closed and verified — ideally with a live penetration test re-confirming the two RLS fixes, not just a second static read — a small, monitored pilot is a reasonable next step, with the P1 list actively tracked in parallel before any broader rollout.
