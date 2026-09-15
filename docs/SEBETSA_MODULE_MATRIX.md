# Sebetsa Module Matrix

Authoritative technical map of Sebetsa as it exists in the repository today (audited 2026-09-15, against `main` commit `74b957f`). This is a companion to [`PRODUCTION_READINESS_AUDIT.md`](./PRODUCTION_READINESS_AUDIT.md) — read that for narrative findings; this file is the reference table.

**Status legend:** 🟢 Production-ready · 🟡 Functional with known gaps · 🔴 Not production-ready / broken · ⚫ Dormant/dead code

---

## Authentication & Identity

| | |
|---|---|
| Routes | `/login`, `/forgot-password`, `/reset-password`, `/activate-account`, `/verify-email`, `/mfa-challenge` |
| Tables | `auth.users` (Supabase-managed), `profiles` |
| Key RPCs | `admin_create_user`, `admin_update_user_role`, `provision_employee_login` (all SECURITY DEFINER, correctly locked to `authenticated` only as of `20260918090100`) |
| Edge Functions | none |
| Roles | all (public entry points) |
| Permissions | n/a (pre-tenant) |
| RLS | `profiles` self-service column-scoped via GRANT + `prevent_direct_role_change`/`prevent_direct_tenant_change` triggers — solid |
| Tests | E2E: `login.spec.ts`, `forgot-password.spec.ts`, `reset-password.spec.ts`, `verify-email.spec.ts`, `activate-account.spec.ts`, `mfa.spec.ts` — **all import the broken legacy `mockAuth` utility** (wrong localStorage key, nonexistent `'principal'` role), not provably passing. Zero unit or RLS coverage of the auth flow itself. |
| Known gaps | MFA "required" for platform_administrator/organization_administrator/hr_user is a dismissible UI banner only — **no server-side assurance-level (`aal`) check exists anywhere in the schema**; a privileged account that never enrolls MFA is never challenged. |
| Status | 🟡 Password reset/activation flow itself is sound (forces re-auth after change) — but MFA enforcement gap is HIGH and test coverage is effectively zero. |

## Multi-Tenancy / Organizations

| | |
|---|---|
| Routes | `/organizations` |
| Tables | `organizations`, `profiles.tenant_id` |
| Key RPCs | tenant resolution via `current_tenant_id()`, `is_platform_admin()` (both SECURITY DEFINER, RLS-recursion-safe) |
| RLS | `ENABLE + FORCE ROW LEVEL SECURITY` on all 60 tables (verified) — but see Critical findings: at least 2 policy classes fail to actually bind to tenant/role correctly |
| Tests | RLS: `org_hierarchy.sql` (never executes — no `run.sh`). E2E: `tenant.spec.ts` — broken `mockAuth`. |
| Known gaps | **CRITICAL**: `employees_write_by_manager` policy's `hr_user` branch has no tenant comparison — cross-tenant read/write/delete of the entire `employees` table. **CRITICAL**: 12+ tables (see RBAC section) have blanket "any tenant member" SELECT with no role check, exposing internal data to `client_user`/`employee`. `organizations` cascade-deletes the entire tenant graph (including `audit_log`) with no soft-delete path. |
| Status | 🔴 The two cross-tenant RLS bugs alone make this NOT production-ready until fixed. |

## People (Employees, Departments, Positions, Teams, Users/Roles)

| | |
|---|---|
| Routes | `/users`, `/users/:id`, `/employees`, `/employees/:id`, `/employees/departments`, `/employees/positions`, `/teams`, `/teams/:id` |
| Tables | `employees`, `departments`, `positions`, `teams`, `team_members`, `profiles` |
| Key RPCs | `terminate_employee`, `reactivate_employee`, `admin_update_user_role` |
| RLS | `validate_employee_tenant_refs`/`validate_team_tenant_refs`/etc. triggers correctly enforce cross-tenant FK integrity. `employees_select_within_tenant`/`employees_write_by_manager` are the two CRITICAL policy bugs (see Multi-Tenancy). |
| Tests | Unit: `positionSchema.test.ts` only (no Employee schema test). RLS: `workforce_management.sql` (unexecuted). E2E: `employees.spec.ts`, `users.spec.ts` — both broken `mockAuth`. |
| Known gaps | **CRITICAL**: `terminate_employee()` sets `profiles.status='inactive'` but that field is never checked anywhere — terminated employees retain full application access (can clock in, submit leave, complete tasks indefinitely). **HIGH**: no DB-level transition trigger on `employees.employment_status`, so a direct table write can flip status illegally, bypassing the termination RPC entirely. **MEDIUM**: no duplicate-person prevention beyond `(tenant_id, employee_number)` uniqueness — no ID/email uniqueness. |
| Status | 🔴 The terminated-employee-retains-access bug is CRITICAL for a workforce/security platform. |

## Site Operations (Site Assignments)

| | |
|---|---|
| Routes | `/site-assignments`, `/site-operations` |
| Tables | `site_assignments`, `site_staffing_requirements` |
| Key RPCs | none — frontend does raw `supabase.from('site_assignments').insert()` |
| RLS | Tenant FK validated via trigger; `site_assignments_select_within_tenant` is one of the 12+ blanket-SELECT-policy tables |
| Tests | RLS: `workforce_site_operations.sql` (unexecuted). E2E: `site-operations.spec.ts` (genuine auth utility, unproven in CI). |
| Known gaps | **CRITICAL**: no overlap/exclusion constraint (two concurrent assignments for one employee are possible), no check the site is `active`, no check the employee is `active`, and **no contract-validity gate at all** — an assignment can be created against a terminated/expired contract or an offboarded site. Combined with the employment-status gap above, a terminated employee can be freshly assigned to a site with zero rejection at any layer. |
| Status | 🔴 Essentially unenforced business rules in a domain whose entire purpose is "who is legitimately deployed where." |

## Scheduling

| | |
|---|---|
| Routes | `/schedule`, `/schedule/mine`, `/schedule/definitions`, `/schedule/availability` |
| Tables | `shifts`, `shift_definitions`, `shift_substitutions`, `employee_availability`, `employee_availability_exceptions` |
| Key RPCs | shift CRUD via direct table writes gated by `shifts_no_overlap` EXCLUDE constraint and `shifts_leave_conflict_guard` trigger |
| RLS | `validate_shift_tenant_refs`; `shifts_select_within_tenant` is one of the 12+ blanket-SELECT tables (company-wide schedule visible to any tenant member) |
| Tests | Unit: `shiftSchema.test.ts`, `shiftDefinitionSchema.test.ts`, `shiftTime.test.ts`, `weekRange.test.ts` — solid, passing. RLS: `scheduling.sql` (unexecuted). **E2E: none exist at all** — no spec file covers shift creation/scheduling flows. |
| Known gaps | **Genuinely well-engineered**: real Postgres EXCLUDE constraint prevents double-booking (not app-level), overnight shifts correctly modeled via `timestamptz`, leave-conflict guard blocks scheduling into approved leave with an audited override. **HIGH gaps**: no check the employee is actually `site_assignments`-linked to the site being scheduled; no `employment_status` check (terminated employees schedulable); recurring weekly `employee_availability` is 100% advisory — never enforced by any trigger. |
| Status | 🟡 Best-engineered domain at the DB-constraint level, undermined by missing cross-domain checks and zero E2E coverage. |

## Attendance

| | |
|---|---|
| Routes | `/attendance`, `/attendance/mine`, `/attendance/corrections` |
| Tables | `attendance_records`, `attendance_breaks`, `attendance_corrections`, `attendance_policies` |
| Key RPCs | `clock_in`, `clock_out`, `request_attendance_correction`, `decide_attendance_correction`, `compute_attendance_metrics` |
| RLS | Correctly hardened in `attendance_rls_hardening.sql` (narrowed from an earlier over-broad policy — a good precedent the `employees` table never received) |
| Tests | Unit: `calculations.test.ts`. RLS: `attendance_time_management.sql` (unexecuted). E2E: `attendance.spec.ts` (genuine), `mobile.spec.ts` (genuine, concrete touch-target + modal-width assertions), `staff-attendance.spec.ts` (broken `mockAuth`). |
| Known gaps | **CRITICAL** (shared root cause with Employees): no `employment_status` check in `clock_in()` — terminated employees can clock in indefinitely. **HIGH**: no site-assignment check on clock-in (can clock in at any site in the tenant); clocking in during already-approved leave is not blocked/flagged (silent contradictory state); self-approval of attendance corrections is not blocked server-side (only role-checked, not requester-vs-approver). **MEDIUM**: a direct-write escape hatch (`attendance_records_write_by_manager`) lets managers bypass the two-party correction workflow entirely; no future-date validation on corrections. **GOOD**: duplicate/concurrent clock-in is blocked by a real partial unique index, not just app logic; worked/late/overtime minutes are always server-computed. |
| Status | 🟡 Strong low-level integrity (duplicate clock-in, metrics computation) undermined by the same terminated-employee and self-approval gaps as elsewhere. |

## Leave

| | |
|---|---|
| Routes | `/leave`, `/leave/team`, `/leave/management`, `/leave/configuration` |
| Tables | `leave_types`, `leave_policies`, `leave_requests`, `leave_balances`, `leave_balance_transactions` |
| Key RPCs | `submit_leave_request`, `approve_leave_request`, `reject_leave_request`, `revoke_leave_request`, `cancel_leave_request`, `adjust_leave_balance` |
| RLS | Best-engineered business-logic domain in the codebase — ledger-vs-snapshot balance design, forced-pending-on-insert, row-locked approval RPCs, idempotency guards |
| Tests | Unit: `leaveRequestSchema.test.ts`, `duration.test.ts`. RLS: `leave.sql` (661 lines, genuinely thorough — unexecuted). E2E: `leave.spec.ts` (genuine, 10 tests, largest genuine E2E file), `mobile.spec.ts` (leave-request modal at phone width). |
| Known gaps | **HIGH**: `approve_leave_request()` never compares approver to requester — a manager-tier user who is also an employee can approve their own leave. **HIGH**: never checks against `leave_balances.remaining` before approving — can drive balance negative. **MEDIUM**: `submit_leave_request()` has a bug where a first-ever request for an employee/type/year silently fails to record the "pending" balance (missing upsert pattern used everywhere else in the same file). **MEDIUM**: no overlapping-leave-request prevention. |
| Status | 🟡 The best-designed module overall (transition triggers, idempotency, real leave↔scheduling integration), let down by the missing self-approval check and one confirmed balance-tracking bug. |

## Tasks

| | |
|---|---|
| Routes | `/tasks`, `/tasks/management` |
| Tables | `tasks`, `task_checklist_items`, `task_evidence` |
| Key RPCs | `complete_task`, `verify_task`, `reassign_task`, `generate_recurring_tasks`, `escalate_overdue_tasks` |
| RLS | `validate_task_tenant_refs` |
| Tests | RLS: `tasks_workflows.sql` (unexecuted). E2E: `tasks.spec.ts` (genuine), `mobile.spec.ts` (touches tasks). |
| Known gaps | **HIGH**: `verify_task()` never checks the verifier differs from the completer/assignee — a supervisor assigned their own task can complete and verify it themselves. **MEDIUM**: task assignment/reassignment never checks `site_assignments` — can cross site boundaries within a tenant. **GOOD**: status lifecycle is a genuine DB-enforced state machine; checklist/evidence requirements are server-checked, not UI-trusted; overdue escalation is real and actually invoked from the frontend (not dead code). |
| Status | 🟡 Solid state machine, same recurring self-verification gap as other domains. |

## Documents

| | |
|---|---|
| Routes | `/documents`, `/documents/manage` |
| Tables | `employee_documents` |
| Storage | `employee-documents` bucket (private) |
| Key RPCs | `create_document_upload_slot`, `verify_document`, `replace_document`, `sync_expired_documents` |
| RLS | The most rigorously enforced domain: metadata RLS correctly restricts `medical`/`disciplinary` types to `organization_administrator`/`hr_user` only (narrower than the general management tier) |
| Tests | RLS: `employee_documents.sql` (unexecuted). E2E: `documents.spec.ts` (genuine, 5 tests), `document-upload.spec.ts` (broken `mockAuth`). |
| Known gaps | **HIGH**: the `storage.objects` RLS policy does **not** replicate the medical/disciplinary sensitivity split the metadata table enforces — `operations_manager` (excluded at the metadata layer) can bypass it by calling the Storage API directly (`.storage.from(...).list()`/`createSignedUrl()`), relying entirely on "the frontend won't ask" rather than a DB guarantee. **MEDIUM**: no magic-byte content-sniffing (self-acknowledged, deferred). **MEDIUM**: expiry sweep is only triggered on-demand when someone opens the management page, not scheduled. |
| Status | 🟡 Best-designed sensitivity model in the app at the metadata layer, undermined by a real storage-layer bypass for a documented-as-restricted role. |

## Compliance & Incidents

| | |
|---|---|
| Routes | `/incidents`, `/compliance` |
| Tables | `incidents`, `incident_affected_employees`, `incident_actions`, `compliance_records` |
| Key RPCs | `report_incident`, `verify_incident_action`, `upsert_compliance_record`, `verify_compliance_record`, `sync_expired_compliance_records` |
| RLS | Status lifecycle DB-enforced end to end |
| Tests | RLS: `compliance_incidents.sql` (unexecuted — and its own "self-verify" test asserts the wrong scenario, see gaps). E2E: `incidents.spec.ts` (4 tests), `compliance.spec.ts` (3 tests) — thinnest E2E coverage in the app. |
| Known gaps | **HIGH**: `verify_compliance_record()` never checks the verifier differs from `responsible_profile_id` — **directly contradicts its own migration comment**, which explicitly claims self-verification is blocked. The RLS test suite's "non-manager cannot self-verify" section tests role-tier gating, not the actual self-verification scenario, so this gap is invisible to the test suite as written. **HIGH**: `sync_expired_compliance_records()` is fully implemented but never called from the frontend — a `compliant` record past its `expiry_date` shows as compliant indefinitely. **MEDIUM**: incidents have no HR-sensitivity visibility split analogous to documents (any operational manager sees full incident detail including injury/medical notes). |
| Status | 🔴 The false "cannot self-verify" claim plus the dead expiry sweep make this domain materially weaker than its own documentation asserts. |

## Assets, Inventory & Procurement

| | |
|---|---|
| Routes | `/assets`, `/inventory`, `/procurement` |
| Tables | `assets`, `asset_assignments`, `inventory_movements`, `procurement_requests` |
| Key RPCs | `assign_asset`, `return_asset`, `record_inventory_movement`, `decide_procurement_request` |
| RLS | Procurement is the **best-implemented self-approval control in the codebase** — `decide_procurement_request()` explicitly blocks approving your own request |
| Tests | RLS: `procurement_inventory_assets.sql` (unexecuted). E2E: `assets.spec.ts` (4 tests), `procurement.spec.ts` (3 tests) — both genuine, thin. |
| Known gaps | **HIGH**: `asset_assignments` is the **one relationship table with no cross-tenant validation trigger** in the entire schema — every other domain got this treatment, this one didn't. **MEDIUM**: no cross-site check on asset assignment. **GOOD**: append-only signed inventory ledger with a negative-balance guard; asset lifecycle is a real DB-enforced state machine; can't assign an already-assigned asset. |
| Status | 🟡 Procurement's self-approval control is the standard every other domain should be raised to; Assets has the one glaring missing tenant-validation trigger in the codebase. |

## Workforce Development (Training/Skills/Performance)

| | |
|---|---|
| Routes | `/development`, `/development/manage` |
| Tables | `employee_skills`, `employee_qualifications`, `training_requirements`, `training_enrollments`, `performance_reviews`, `development_actions` |
| Key RPCs | `set_employee_skill`, `verify_employee_skill`, `upsert_employee_qualification`, `verify_employee_qualification`, `advance_performance_review`, `sync_expired_qualifications` |
| RLS | HR-visibility boundary (`can_manage_employees()`, excluding the operational tier) verified **correctly and consistently implemented** — confirms the codebase's own claim |
| Tests | RLS: `workforce_performance_training_skills.sql` (unexecuted). E2E: `workforce-development.spec.ts` (4 tests, genuine). |
| Known gaps | **HIGH**: certification/qualification expiry has zero downstream effect — `training_requirements` (a catalogue of what's required per role/site) is never joined against `shifts` anywhere, so an employee with an expired required certification can still be freely scheduled. **MEDIUM**: same self-verification gap as elsewhere (`verify_employee_skill`/`verify_employee_qualification` don't check verifier ≠ subject). **GOOD**: `performance_reviews` has a genuine hard finalization lock and stage-aware authorization (employee's own acknowledgement step can only be taken by that employee). |
| Status | 🟡 Privacy boundary is a genuine strength; the "required training" catalogue is currently decorative since nothing enforces it operationally. |

## Analytics & Reporting

| | |
|---|---|
| Routes | `/reports` |
| Tables | (read-only aggregation over existing tables) |
| Key RPCs | `get_operational_metrics()` — the deliberate, well-reasoned SECURITY INVOKER exception |
| RLS | Relies on the RLS of the underlying tables (by design) |
| Tests | RLS: `analytics_reporting.sql` (unexecuted). E2E: `reports.spec.ts` (4 tests, genuine). |
| Known gaps | **LOW**: a non-manager caller gets misleading single-row-scoped aggregates rather than an error (by design, but a UX trap). Frontend (`reportsService.ts`) correctly calls the RPC and does not duplicate aggregation client-side — this **disproves** an initial hypothesis that reporting re-implements the RPC's work in JS. |
| Status | 🟢 Genuinely sound design (confirmed, not just claimed) — the one module with no material integrity finding. |

## Notifications

| | |
|---|---|
| Routes | `/notifications`, `/notifications/settings` |
| Tables | `notifications`, `notification_preferences` |
| Key RPCs | `create_notification` (correctly locked from `authenticated`/`anon` — only callable from inside other privileged RPCs) |
| Edge Functions | `notifications-dispatch` — see below |
| RLS | `notifications` SELECT/UPDATE is `recipient_profile_id = auth.uid()` only — the strictest possible shape, verified clean |
| Tests | **RLS: no test file exists for notifications at all** in `supabase/rls-tests/`, despite `notificationService.ts`'s own comment naming RLS as the actual enforcement mechanism. E2E: `notifications.spec.ts` — broken `mockAuth`. |
| Known gaps | The `notifications-dispatch` Edge Function queries a `notification_deliveries` table that **does not exist anywhere in the 46 live migrations** — confirmed dead/non-functional code, deployed-looking, referenced by `docs/COMMUNICATION.md`/`docs/NOTIFICATIONS_DELIVERY.md` (Funda360-era docs describing a schema that was never ported). Fails safe (missing-secret and missing-table checks both fail closed), but it's dead weight, not a working delivery worker. |
| Status | ⚫ In-app notifications work and are correctly isolated; the multi-channel delivery worker is entirely non-functional and untested at every layer. |

## Payments (dormant)

| | |
|---|---|
| Routes | **none** — no frontend route or component references payments anywhere |
| Tables | `payment_intents`, `payment_gateway_configs`, `settle_payment_intent` RPC — **none exist in the 46 live Sebetsa migrations** (only in `docs/funda360-reference-migrations/`) |
| Edge Functions | `payments-initiate`, `payments-webhook`, plus 5 provider adapters (PayFast/Ozow/Yoco/Peach/Netcash) in `_shared/providers/` |
| Known gaps | **Confirmed fully orphaned**: both functions reference tables/RPCs that don't exist in the live schema — any invocation fails at the first database call. `payments-initiate` still uses Funda360's schema shape (`school_id`, a `learners` table, "School fees" line-item text). The provider adapters themselves implement genuine, good-quality constant-time signature verification for all 5 gateways — that part is real engineering, just unreachable. **HIGH**: `payments-initiate` leaks raw exception text to callers; the entire settlement safety net (signature-gate enforcement, amount re-verification, idempotency) is described only in code comments referencing `settle_payment_intent()`, which was never written; CORS is wildcarded on the one function meant to be browser-invoked. CI still `deno check`s these files. |
| Status | ⚫ Not production-ready. Do not deploy or wire up until the schema is either ported for real or the functions are removed — and the three defects above are fixed regardless, since they'd ship live on day one otherwise. |

---

## Cross-cutting infrastructure

| Component | Status | Note |
|---|---|---|
| CI (`.github/workflows/ci.yml`) | 🔴 | Red on `main` HEAD: typecheck/lint/unit/build job passes; e2e job fails (179/261); edge-functions job fails typecheck (missing `admissions-public`); RLS-regression job fails instantly (missing `run.sh`); GitHub Pages deploy job fails (missing secrets). |
| RLS test suite (`supabase/rls-tests/`) | 🔴 | 13 well-written, genuinely thorough `.sql` files — zero execution path in CI (the runner script only exists archived under `docs/funda360-reference-other/`). |
| E2E suite (`e2e/`) | 🔴 | 54 spec files; only 14 (26%) use the correct auth utility; even those are unproven given the unfiltered, currently-failing CI run. |
| Documentation (`docs/`) | 🔴 | No Sebetsa-native architecture doc exists. ~68% of `docs/` by size is archived Funda360 material sitting inside the primary tree. `DOMAIN_STATUS.md` actively instructs a future session to resume building Funda360 school features. |
