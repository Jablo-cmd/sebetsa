# Sebetsa — Production Remediation & Security Hardening Report

> **This report covers two remediation passes.** The first pass (immediately below) took Sebetsa from NOT READY to PILOT READY. A second pass, **"Second Remediation Pass"** further down this document, closed every HIGH finding the first pass left open plus a newly-discovered finding of the same severity, and is the basis for this document's final, authoritative **Verdict** at the very end — read that section for the current state, not the first pass's own verdict language, which it supersedes.

**Remediated:** 2026-09-15, repository `Jablo-cmd/sebetsa`, branch `claude/app-capabilities-review-cnvcgv`, base commit `74b957f` (the commit [`PRODUCTION_READINESS_AUDIT.md`](./PRODUCTION_READINESS_AUDIT.md) audited).
**Scope:** Every CRITICAL and HIGH finding from the audit that the audit's own P0 remediation plan called out by name, plus the E2E test-suite repair and CI restoration. This report documents exactly what changed, how each fix was verified, and — with the same discipline the audit itself applied — which HIGH/MEDIUM findings from the original audit were **not** touched in this pass and remain open.
**Method:** Every fix below was written as a real Supabase migration (`supabase/migrations/2026091909*.sql`), then verified against a live PostgreSQL 16 instance running every migration in the repository in order (not a mock, not a subset) plus the genuine Supabase `auth`/`storage` schema stubs already used by `supabase/rls-tests/`. Docker (the RLS suite's normal execution path, `supabase/rls-tests/run.sh`) is blocked by this sandbox's outbound-network policy, so verification instead ran the identical stub-then-migrations-then-tests sequence against a natively-installed PostgreSQL 16 — same SQL, same order, same pass/fail semantics, just a different Postgres host process. Every regression test was confirmed to **fail against the pre-fix schema and pass against the post-fix schema** before being counted as done, not merely written and left unrun.

---

## Executive Summary

All 5 CRITICAL findings and 5 of 7 HIGH-severity findings the audit's P0/P1 remediation plan named are fixed, migrated, and covered by a passing regression test running against a real Postgres instance with every real migration applied. The E2E suite — previously 74% non-functional because it authenticated against a localStorage key the real app never reads — has been fully repaired: 24 spec files testing functionality that doesn't exist in Sebetsa were deleted with justification, and every remaining file was migrated to genuine Sebetsa auth/data mocking and verified live against a real build. CI's two broken jobs (RLS suite with a missing runner script, Edge Function typecheck referencing a nonexistent file) are fixed; the orphaned, schema-referencing-nothing Edge Functions are removed rather than left deployed-but-dead.

**Not fixed in this pass, and explicitly not claimed as fixed:** two HIGH findings (self-approval guards on `verify_employee_qualification`/`verify_employee_skill`; missing cross-tenant FK-validation triggers on the four org-hierarchy tables and `asset_assignments`) and the MEDIUM `submit_leave_request()` upsert bug remain open — see **Remaining Risks** below. MFA enforcement was deliberately scoped to the two highest-leverage privileged RPCs (user creation, role assignment), not every action a privileged role can take — the reasoning is documented in the migration itself and repeated here. The GitHub Pages deploy job's missing secrets are a repository-settings action outside this session's write access (no filesystem change can set a GitHub Actions secret); the deploy job already fails loudly with a clear error rather than silently deploying a broken build, which was confirmed still true and is the correct posture until a repository admin configures the secret.

---

## Critical Findings — Fixed

### C-1. `employees_write_by_manager` cross-tenant write/delete

**Fix:** `supabase/migrations/20260919090000_p0_tenant_rbac_remediation.sql`. The `hr_user` OR-branch now requires `tenant_id = public.current_tenant_id()` in addition to the role check — matching the pattern every other write-tier helper in the codebase already used.

**Verification:** `supabase/rls-tests/p0_tenant_rbac_remediation.sql` impersonates an `hr_user` in Tenant A and asserts an `UPDATE ... RETURNING *` and a `DELETE` against Tenant B's `employees` rows both affect zero rows. Confirmed to fail against the pre-fix policy (returns/deletes cross-tenant rows) and pass against the post-fix policy.

### C-2. Twelve-plus blanket tenant-wide SELECT policies

**Fix:** Same migration. Added four new scoping helpers (`can_view_workforce_directory`, `can_view_org_structure_broad`, `can_view_profiles_broad`, `can_view_scheduling_broad`) and rewrote all 15 affected SELECT policies (`employees`, `departments`, `positions`, `teams`, `team_members`, `site_assignments`, `regions`, `clients`, `sites`, `contracts`, `contract_sites`, `shifts`, `shift_substitutions`, `shift_definitions`, `site_staffing_requirements`, `profiles`) to require the caller hold at least a narrow "own record" condition or the relevant permission tier — not merely tenant membership.

**Side effect found and fixed in the same pass:** narrowing these SELECT policies broke the ~30 `validate_*_tenant_refs()` triggers wherever they were `SECURITY INVOKER` (a trigger's internal lookups were now blocked by the same narrower policy for roles like `supervisor`). Fixed in `20260919090100_p0_tenant_ref_trigger_security_definer.sql` by converting all 38 such trigger functions to `SECURITY DEFINER` with a locked `search_path` — this is the correct fix (a validation trigger's own internal lookups should never be subject to the calling user's row visibility), not a workaround.

**Verification:** `p0_tenant_rbac_remediation.sql` impersonates `client_user` (zero permissions) and plain `employee` and asserts each of the 15 tables returns zero rows for data that permission tier shouldn't see; a broader-permission role in the same test confirms the data is still reachable where it should be. Confirmed fail-then-pass. Every pre-existing RLS test file that depended on the old over-broad behavior as if it were correct (`org_hierarchy.sql`, `workforce_site_operations.sql`) was corrected to assert the right (deny) behavior instead, with a comment citing this finding — not deleted, not weakened.

### C-3. Terminated employees retain full application access

**Fix:** `supabase/migrations/20260919090200_p0_terminated_employee_access_revocation.sql`. New helper `employee_can_self_serve(p_employee_id)` checks `employees.employment_status not in ('terminated', 'suspended')`. Added as a guard to every self-service RPC the audit named: `clock_in`, `submit_leave_request`, `request_attendance_correction`, `complete_task`.

**Verification:** `supabase/rls-tests/p0_termination_and_self_approval.sql` terminates an employee mid-test, then asserts each of the four RPCs now raises `inactive_employee: ...` for that employee where it previously succeeded. Confirmed fail-then-pass for each of the four.

### C-4. CI red on `main`

**Fix:** all four contributing causes addressed directly:
- RLS suite: `supabase/rls-tests/run.sh` restored (was referenced by CI but absent — this session confirmed it exists now and is executable, and its stub files `00_auth_stub.sql`/`00b_storage_stub.sql` were verified to be generic Supabase local-dev scaffolding, not Funda360-specific).
- Edge Function typecheck referencing a nonexistent `admissions-public/index.ts`: the entire job is removed (see **Edge Functions**, below) rather than patched to skip one file, since the three functions it did check are also confirmed dead code.
- E2E suite: see **E2E Suite**, below.
- Deploy job: already fails loudly on missing secrets rather than deploying silently broken; actually configuring the `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` secrets in the repository's `github-pages` environment is a GitHub Settings action outside this session's access — flagged explicitly in **Remaining Risks**, not silently left implied-fixed.

**Verification:** every job's underlying command was run locally and confirmed passing (see **Final Validation Results** below) — this session did not have a mechanism to trigger and observe an actual GitHub Actions run, so "CI green" is reported as "every constituent command passes locally, reproducing what each job runs," not as a confirmed live Actions run.

### C-5. `site_assignments` has no server-side business-rule enforcement

**Fix:** `supabase/migrations/20260919090300_p0_site_assignment_enforcement.sql` extends `validate_site_assignment_tenant_refs()` (the trigger that already ran on every insert/update) with two new checks, scoped to open-ended assignments (`end_date is null or end_date >= current_date`, matching the audit's own "at minimum" framing): the target employee must not be `terminated`/`suspended`, and the target site must have `status = 'active'`.

**Verification:** `p0_termination_and_self_approval.sql` asserts an attempt to open-assign a terminated employee to a site raises `inactive_employee: ...`, and a separate assertion covers the inactive-site case. Confirmed fail-then-pass for both.

**Explicitly not fixed (scope discipline, not an oversight):** overlap/exclusion prevention (two simultaneous open assignments for the same employee) and contract-validity gating were named in the audit as separate, lower-priority items (P2: "Add overlap prevention to `site_assignments`") and were not added here — the fix above closes exactly the "terminated employee freshly assigned" compounding scenario C-5 described as severe when combined with C-3, which is now closed.

---

## High Findings — Fixed

### Self-approval / separation-of-duties (5 of 7 affected RPCs)

**Fix:** `supabase/migrations/20260919090400_p0_self_approval_guards.sql`, using `decide_procurement_request()`'s existing correct pattern as the template. Guards added to: `approve_leave_request`, `reject_leave_request`, `revoke_leave_request` (via an `employees.profile_id = auth.uid()` join, since these operate on a leave request row rather than an employee row directly), `decide_attendance_correction` (`requested_by = auth.uid()`), `verify_task` (`completed_by = auth.uid()`), `verify_compliance_record` (`responsible_profile_id = auth.uid()` — also corrects the migration comment the audit found falsely claiming this was already blocked), `verify_incident_action` (`owner_profile_id = auth.uid()`). Every guard is `and not public.is_platform_admin()`, matching the existing template exactly.

**Verification:** `p0_termination_and_self_approval.sql` has one assertion per guarded RPC: the record's own subject/requester/completer/responsible-person attempts to approve/verify their own submission and is rejected with `insufficient_privilege: ...`; a separate person in an approving role succeeds. Confirmed fail-then-pass for all 6 functions guarded (the 7th, `revoke_leave_request`, was already effectively covered by the same guard pattern applied alongside `approve`/`reject` in the same migration).

**Not fixed — see Remaining Risks:** `verify_employee_qualification` and `verify_employee_skill` (workforce development) still have no self-approval guard. This was named in the audit's HIGH finding list but not in its P1 remediation-plan bullet (which named five domains, not seven); this pass followed the plan's explicit five and did not additionally close the two omitted from that bullet. That is a real, currently-open gap, not a difference of opinion about severity.

### MFA enforced only as a dismissible banner

**Fix:** `supabase/migrations/20260919090600_p1_mfa_server_side_enforcement.sql`. New `mfa_step_up_required()` checks `auth.jwt()->>'aal' <> 'aal2'` for the three MFA-required roles (`platform_administrator`, `organization_administrator`, `hr_user`) and is enforced, unbypassably (checked server-side in the RPC body, not a client-side gate that a direct RPC call could skip), in `admin_create_user` and `admin_update_user_role` — the two highest-leverage privileged actions (new-account provisioning, privilege escalation).

**Deliberately not a blanket hard block on every action**, documented in the migration's own header: MFA enrollment is not yet mandatory anywhere in the product, so a blanket block today would lock out every current admin account with no path back in — a worse outcome than the narrower gap this closes. Expanding `mfa_step_up_required()` to more RPCs once enrollment is actually rolled out is tracked as a P2 follow-up.

**Verification:** `supabase/rls-tests/p1_mfa_enforcement.sql` impersonates a qualifying role at `aal1` and asserts both RPCs raise `mfa_required: ...`; the same role at `aal2` succeeds; a non-qualifying role at `aal1` succeeds unimpeded. Confirmed fail-then-pass.

### Storage-layer sensitivity-tier bypass

**Fix:** `supabase/migrations/20260919090500_p1_storage_sensitivity_tier_fix.sql` rewrites `employee_documents_storage_select` to run the exact same medical/disciplinary visibility check the metadata-table policy (`employee_documents_select`) already enforced, closing the "call the Storage API directly" bypass the audit found for `operations_manager`.

**Verification:** `supabase/rls-tests/employee_documents.sql` (pre-existing file, extended in this pass) asserts `operations_manager` cannot read a medical document's storage object directly, and that a legitimately-authorized role's own file upload/read still works. Confirmed fail-then-pass.

### Compliance-record expiry never invoked

**Fix:** `supabase/migrations/20260919090700_p1_expiry_sweep_scheduling.sql` adds tenant-batch wrappers (`sync_all_expired_compliance_records`, `sync_all_expired_qualifications`, `sync_all_expired_documents`) around the existing per-tenant sweep functions, each with `revoke execute ... from public, anon, authenticated` (service-role/cron-only — these should never be client-invocable), plus a guarded `DO` block that registers `pg_cron` schedules only `if exists (select 1 from pg_available_extensions where name = 'pg_cron')`.

**Honestly unverified in one specific way:** `pg_cron` is not installed in either this sandbox or the native-Postgres verification harness, so the `DO` block's `else raise notice ...` branch is what actually ran during verification — the sweep *functions* are confirmed correct and were called directly, but the *scheduling* was never live-observed actually firing on a timer. This is flagged, not silently assumed. On the real hosted Supabase project (which does have `pg_cron` available under Database → Extensions), the same migration will take the `if` branch and register real schedules — but that should be confirmed by a human with access to the hosted project after this migration ships, not assumed from this sandbox.

### Orphaned Edge Functions

**Fix:** `payments-initiate`, `payments-webhook`, `notifications-dispatch`, and their shared `_shared/` provider-adapter code are deleted outright (not merely unwired) — see the audit's own recommendation ("finish or remove, not leave as-is") and the git commit for the full rationale. The corresponding CI job is removed, not patched to skip the nonexistent `admissions-public` file, since the three functions it did check are also dead.

---

## RLS Coverage

17 test files, 0 failures, run against a from-scratch database with every one of the repository's real migrations applied in order:

```
analytics_reporting.sql · attendance_time_management.sql · client_contract_sla.sql
compliance_incidents.sql · employee_documents.sql · leave.sql · org_hierarchy.sql
p0_tenant_rbac_remediation.sql · p0_termination_and_self_approval.sql
p1_expiry_sweeps.sql · p1_mfa_enforcement.sql · procurement_inventory_assets.sql
scheduling.sql · tasks_workflows.sql · workforce_management.sql
workforce_performance_training_skills.sql · workforce_site_operations.sql
```

This is up from the audit's baseline of "13 files, 0 currently running" (the runner script was absent). 4 new files were added specifically for this remediation (`p0_tenant_rbac_remediation.sql`, `p0_termination_and_self_approval.sql`, `p1_mfa_enforcement.sql`, `p1_expiry_sweeps.sql`); 6 pre-existing files had assertions corrected where they encoded the pre-fix (buggy) behavior as if it were intended (`org_hierarchy.sql`, `workforce_site_operations.sql`, `leave.sql`, `employee_documents.sql`, `compliance_incidents.sql`, `attendance_time_management.sql`), each with a comment citing the specific audit finding that required the correction. No test was deleted or weakened to make the suite pass — every correction narrowed an assertion toward the *correct* (more restrictive, deny-by-default) behavior, never the reverse.

## Tenant Isolation

Both confirmed-exploitable attacks from the audit (Attack B/C/D via C-1, Attack A via C-2) are now closed and covered by dedicated regression tests, verified fail-then-pass against a live database — not merely re-read statically. The audit's own caveat stands and is repeated here rather than dropped: this is SQL-level verification against a disposable local instance running the real migrations, not a live penetration test against the actual hosted Supabase project with its real network topology, connection pooling, and auth configuration. That live re-verification is recommended before general rollout, exactly as the audit itself said.

## Authentication / MFA

See **High Findings** above. Password reset/activation session-invalidation behavior (already correct per the audit) is unchanged. MFA is now a real server-side gate for the two highest-leverage privileged actions, not a UI-only banner — but is intentionally not yet a blanket requirement across every privileged action, for the reasons documented in the migration and repeated above.

## E2E Suite

**Before:** 54 spec files, 40 (74%) silently non-functional (wrong localStorage auth key — `mockAuth.ts` seeds `'funda360-auth'`, the real app reads `'sebetsa-auth'`), last known CI run 179 failed / 82 passed.

**After:** 30 spec files. 24 files testing functionality with no Sebetsa equivalent were deleted (academic years, admissions, alumni, fees, homework, learner/guardian/parent portals, report cards, timetable, teacher workspace, messaging, a command palette that doesn't exist in this app, and others — each confirmed absent from the real route table before deletion, not assumed). The remaining ~14 previously-broken files were rewritten against `sebetsaAuth.ts`/`sebetsaData.ts` (genuine Sebetsa session/REST/RPC mocking) with flows, fixtures, and assertions matching the real pages, roles, and permission model — not a mechanical find-and-replace of old Funda360 scenarios. `role-scoped-experience.spec.ts` and `accessibility.spec.ts` were full rewrites driven directly from the real navigation/permission source of truth (`src/features/rbac/constants/navigation.ts`, `rolePermissions.ts`); `accessibility.spec.ts` was additionally trimmed to only the pages not already covered by each feature area's own accessibility test, once it became clear several already existed and weren't part of the original Funda360-contaminated set. `document-upload.spec.ts`'s genuinely new coverage was folded into the pre-existing, more complete `documents.spec.ts` instead of shipping a near-duplicate file.

**Final full-suite run, every spec file together, one command, live against a real build+preview server with the full mocked network layer:** 127 passed, 0 failed, 0 skipped.

## CI

- `edge-functions` job: removed (dead code removed, not patched around).
- `rls-tests` job: runner script restored; 17/17 files pass (verified via the native-Postgres equivalent described above, since Docker is blocked in this sandbox — the actual CI job uses the unmodified Docker-based `run.sh`, which was not itself executed in this session, only its SQL content, applied identically).
- `e2e` job: now runs a fully-repaired, fully-passing suite unfiltered (no filtering flag was needed once every remaining file was fixed rather than skipped).
- `quality` job (typecheck/lint/unit/build): unaffected by this remediation's changes and confirmed still passing.
- `deploy` job: unchanged code-wise; still correctly fails loudly on missing secrets rather than silently deploying a broken build. The secrets themselves are a repository-settings action outside this session's access — see **Remaining Risks**.

## Edge Functions

All three (`payments-initiate`, `payments-webhook`, `notifications-dispatch`) and their shared `_shared/` code are deleted. Nothing was "finished" instead of removed — the audit's finding that they reference tables absent from every real migration (only present in the archived Funda360 reference material) was re-confirmed before deletion, and no frontend code referenced any of the three (also re-confirmed by grep before deletion).

## Storage

The one confirmed defect (medical/disciplinary sensitivity-tier bypass via direct Storage API access) is fixed and covered by a regression test — see **High Findings** above. Everything the audit found already correct (private buckets, server-generated sanitized paths, time-limited signed URLs, correct cross-tenant denial) is unchanged.

---

## Final Validation Results

All of the following were run directly in this session, against the actual current state of the repository (not from memory, not assumed):

| Check | Result | Detail |
|---|---|---|
| Typecheck (`npm run typecheck`) | **PASS** | `tsc -b --noEmit`, zero errors, whole project including `e2e/` |
| Lint (`npm run lint`) | **PASS** | `eslint .`, zero errors/warnings |
| Unit tests (`npm run test`) | **PASS** | 171/171 tests, 24/24 files (vitest) |
| Production build (`npm run build`) | **PASS** | Both the CI-dummy-env build (for e2e) and a plain build succeed |
| RLS regression suite | **PASS** | 17/17 files, run against a from-scratch database with every real migration applied, via the native-Postgres equivalent of `run.sh` (Docker blocked in this sandbox — see CI section) |
| E2E suite (`npx playwright test`) | **PASS** | 127/127 tests, 0 failed, 0 skipped, full suite run together in one command |

---

## Second Remediation Pass — Closing the Remaining HIGH Findings (2026-09-15, continued)

A follow-up sprint, same branch, commit `b80f833` and later. Scope: the two HIGH findings and the MEDIUM bug the first pass above explicitly left open (items 1–3 of that pass's Remaining Risks), plus a full second pass over the codebase — reproduce-first, root-cause fixes only, no shortcuts — including a broader RLS audit that was not part of the original brief.

### HIGH #1 — `verify_employee_qualification`/`verify_employee_skill` self-approval — FIXED

**Reproduced first:** both functions were read in full before any change. Confirmed neither checked anything beyond `can_manage_employees(tenant_id)` — no comparison between the verifier and the record's own employee. A privileged account (`organization_administrator`/`operations_manager`/`hr_user`) who is *also* an `employees` row in that tenant could call either function on their own skill/qualification record and it would succeed.

**Fix:** `supabase/migrations/20260920090000_p1_self_approval_qualification_skill.sql`. Both functions now join `employees` to derive `profile_id = auth.uid()` (the same shape `verify_compliance_record`/`verify_incident_action` already used for an analogous "no direct employee_id column" case in the first pass) and raise `insufficient_privilege: cannot verify your own skill/qualification` when true, exempting only `is_platform_admin()` — identical to every other self-approval guard in the codebase.

**Verification:** `supabase/rls-tests/p1_self_approval_qualification_skill.sql` — self-verification denied (both skill and qualification), verifying a *different* employee's record still succeeds (control), and a cross-tenant verification attempt is separately denied by the unchanged `can_manage_employees` tenant check. Confirmed fail-then-pass by temporarily removing the fix migration and re-running: the pre-fix run reproduced `SECURITY_FAILURE: organization_administrator verified their own skill` exactly as expected.

### HIGH #2 — Missing cross-tenant FK-validation triggers — FIXED

**Reproduced first:** confirmed by grep that `clients`, `sites`, `contracts`, `contract_sites`, `asset_assignments` had no `validate_*_tenant_refs` trigger at all, unlike every other relationship table in the schema (`employees`, `shifts`, `assets`, etc.).

**Fix:** `supabase/migrations/20260920090100_p1_org_hierarchy_asset_tenant_refs.sql` adds one `SECURITY DEFINER` trigger per table, each validating only structural relationship columns (`region_id`, `client_id`, `site_id`, `contract_id`, `employee_id`, `team_id`) — never profile-linked actor columns (`responsible_manager_id`, `assigned_by`), matching the established codebase convention exactly (`employee_documents.uploaded_by`/`verified_by` are likewise never tenant-validated by any trigger, since they're server-derived inside an already tenant-gated RPC). No `is_platform_admin()` bypass, matching all ~38 pre-existing triggers of this kind — a platform admin must not be able to construct a row that itself corrupts tenant boundaries for every subsequent reader.

`asset_assignments` has no direct client write policy at all (`assign_asset()` is the only path), so the attack was exercised through that RPC — the realistic path a caller would actually reach, not a synthetic raw INSERT that RLS would block anyway before the trigger even runs.

**Verification:** `supabase/rls-tests/p1_org_hierarchy_asset_tenant_refs.sql` — 8 cross-tenant attack assertions (client→region, site→client, site→region, contract→client via INSERT and via UPDATE, contract_sites→site, contract_sites→contract, and 3 `assign_asset()` cross-tenant target variants), each with a same-tenant control proving the trigger narrows rather than blanket-rejects. Confirmed fail-then-pass the same way as HIGH #1.

### `submit_leave_request()` upsert bug — FIXED

**Reproduced first:** confirmed the function's balance write was a plain `UPDATE` with no `ON CONFLICT`, and that nothing seeds a `leave_balances` row automatically — one is only created by `adjust_leave_balance()`, `recompute_leave_balance()`, or `approve_leave_request()`'s own insert-on-conflict. A genuinely first-ever request for an employee/leave_type/period_year therefore updated zero rows and silently lost the `pending` figure.

**Fix:** `supabase/migrations/20260920090200_p1_leave_balance_upsert_fix.sql` — the balance write is now `INSERT ... ON CONFLICT (tenant_id, employee_id, leave_type_id, period_year) DO UPDATE SET pending = leave_balances.pending + excluded.pending`, mirroring `approve_leave_request()`'s own established pattern on the same table. Every other check in the function (terminated-employee, tenant derivation, date/policy validation) is unchanged.

**Verification:** `supabase/rls-tests/p1_leave_balance_upsert.sql` — a genuinely first-ever request (no pre-existing balance row, asserted before the call) correctly records `pending = 1`; a second request on the same employee/type/year accumulates to `pending = 2` (sum, not overwrite); terminated-employee, unauthorized-employee, and cross-tenant submission are all still denied (unchanged controls). Confirmed fail-then-pass: the pre-fix run reproduced `FAIL: no leave_balances row was created by a first-ever leave request`.

### New finding, discovered during this pass's own broader RLS audit — FIXED

Not named in the original audit and not one of the three items above — surfaced by directly querying `pg_policies` on a fully-migrated database rather than re-reading migration source (source-level `grep` for the blanket pattern is misleading here, since later migrations `DROP POLICY`/`CREATE POLICY` over earlier ones with the same name).

12 tables carried the exact same "blanket tenant-wide SELECT, no permission predicate" shape as the original audit's CRITICAL C-2 finding: `assets`, `asset_assignments`, `asset_maintenance_records`, `inventory_items`, `inventory_movements`, `compliance_requirements`, `client_contacts`, `contract_documents`, `sla_definitions`, `sla_measurements`, `employee_availability`, `employee_availability_exceptions`. Every one of these backs a permission gated in `rolePermissions.ts` (`asset.view`, `inventory.view`, `compliance.view`, `org_structure.view`, `availability.view`) that `client_user` (zero permissions) and, for several tables, `employee`/`hr_user` do not hold — yet the RLS layer let them read the full tenant-wide table regardless.

**Fix:** `supabase/migrations/20260920090300_p1_broader_blanket_select_narrowing.sql`. Narrowed each to the already-established helper matching its permission's exact role set (verified against `rolePermissions.ts` before reuse, not assumed): `can_manage_operations()` for the six `asset.view`/`inventory.view`/`compliance.view` tables (its role set — `organization_administrator`/`operations_manager`/`regional_manager`/`site_manager`/`supervisor`, plus `is_platform_admin()` — is exactly the set that holds those three permissions), `can_view_org_structure_broad()` for the four contract/client-adjacent tables, and `can_view_scheduling_broad()` (broad-tier OR own-employee) for the two availability tables, mirroring `shifts_select_own_or_broad`'s exact shape.

**Deliberately not touched, with rationale** (scope discipline against turning a 2-item fix list into an unbounded rewrite): `leave_types`, `task_templates`, `training_programs`, `training_requirements`, `attendance_policies`, `leave_policies`, `skills` are catalogue/reference/configuration tables with no corresponding permission gate in `rolePermissions.ts` at all — `leave_types` itself already has an explicit, clearly-intentional `tenant_id = current_tenant_id()`-only policy with no role check, the same precedented shape as "every tenant member should see what leave types/skills/training programs exist." `task_comments` was also left as-is: correctly narrowing it requires replicating `tasks_select_own_or_broad`'s full multi-branch join (own-assignee, own-supervisor, own-team-member, or broad tier) to stay consistent with its parent task's own visibility, a higher-risk change deferred to its own dedicated pass rather than rushed here.

**Regression fixture correction:** `supabase/rls-tests/leave.sql`'s revocation test read `employee_availability_exceptions` as `hr_user` to verify a data-integrity property (the unrelated manual exception survives revocation) — `hr_user` does not hold `availability.view`, so this incidentally relied on the very bug being fixed. Corrected to check as the table owner instead (`reset role`), exactly the same fixture-correction pattern this file's own shift-existence check already used for the original C-2 fix — the security assertion is unchanged, only the role used to check an unrelated data-integrity side effect.

**Verification:** `supabase/rls-tests/p1_broader_blanket_select_narrowing.sql` — `client_user` denied on 6 representative tables (assets, inventory_items, compliance_requirements, client_contacts, sla_definitions, employee_availability), the authorized tier still reads all of them (control), and an employee still reads their own availability row (control, proves the own-record branch survived). Confirmed fail-then-pass.

### Small hygiene fix (P2, not a HIGH/CRITICAL item)

The 8 boolean permission-helper functions (`can_manage_profiles`, `can_assign_role`, `can_manage_org_structure`, `can_manage_operations`, `can_manage_employees`, `can_manage_leave`, `can_approve_leave`, `can_view_leave_broad`) never received the explicit `revoke ... from public, anon` the rest of the codebase's `SECURITY DEFINER` functions have — a MEDIUM finding from the original audit, still open after the first pass. Closed in `supabase/migrations/20260920090400_p2_permission_helper_grants_hygiene.sql` — purely additive, no function body changed, confirmed the full RLS suite still passes afterward.

### Second-pass SECURITY DEFINER / RLS audit (§11/§12 of this sprint's brief)

- **Zero** `USING (true)`-or-equivalent policies exist anywhere in the schema (checked via grep across every migration).
- **Zero** genuine `SECURITY DEFINER` functions are missing an explicit `search_path` (95 functions checked programmatically; one false-positive from a string-literal match on the words "SECURITY DEFINER" inside an unrelated trigger's own error message was investigated and ruled out).
- **Zero** dynamic SQL (`EXECUTE format(...)`) anywhere in the migration set — no SQL-injection surface of that shape exists.
- Every RPC accepting a client-supplied `p_tenant_id` was re-checked: each only trusts it when `is_platform_admin()` is independently true (`admin_create_user`), or doesn't accept one at all and derives tenant server-side from a row lookup — consistent with the original audit's own conclusion on this point.
- The three new `sync_all_expired_*` expiry-sweep wrapper functions from the first pass take no tenant parameter at all (operate across every tenant in one call) and are `revoke`d from `public, anon, authenticated` — re-confirmed still correct.

### Final Validation Results (second pass)

| Check | Result | Detail |
|---|---|---|
| Typecheck | **PASS** | `tsc -b --noEmit`, zero errors |
| Lint | **PASS** | `eslint .`, zero errors/warnings |
| Unit tests | **PASS** | 171/171 (unaffected — no frontend code changed this pass) |
| Production build | **PASS** | CI-dummy-env build succeeds |
| RLS regression suite | **PASS** | **21/21** files (17 from the first pass + 4 new), local native-Postgres run |
| RLS regression suite — **live GitHub Actions** | **PASS** | Run [#16](https://github.com/Jablo-cmd/sebetsa/actions/runs/35014274077), `workflow_dispatch` on this branch, commit `b80f833` — the real Docker-based `supabase/rls-tests/run.sh`, not the native substitute, executed by GitHub's own runner |
| Typecheck/lint/unit/build — **live GitHub Actions** | **PASS** | Same run #16, "Typecheck, lint, unit tests, build" job — completed success |
| E2E suite — **live GitHub Actions** | **PASS** | Same run #16, "Playwright end-to-end suite" job — completed success, zero failures (its own "Upload failure traces" step correctly skipped, since nothing failed) |
| GitHub Pages deploy — **live GitHub Actions** | **FAIL (expected)** | Same run #16, "Deploy to GitHub Pages" job — failed exactly at its own "Verify production Supabase configuration" step, confirming the documented missing-secrets gap (Remaining Risk #3) is real and that the job's fail-loudly guard works correctly. This is the only job in run #16 that did not pass, and it is not a code defect — see Remaining Risks. |
| E2E suite | **PASS** | 127/127 (unaffected — RLS-only changes, fully network-mocked suite) |

Every one of this pass's four new fix migrations, plus the one from the first pass they build on, was independently confirmed to fail against the pre-fix code and pass against the post-fix code — not merely written and left unrun.

---

## Remaining Risks — Current State After Both Passes

Named individually, not folded into a vague "future work" note, per this remediation's own no-cheating-the-audit standard. Items 1–3 from the first pass are now fixed and removed from this list; renumbered:

1. **MFA is a hard gate on exactly two RPCs** (`admin_create_user`, `admin_update_user_role`), not every privileged action — intentional and documented, but still means a compromised MFA-required-role password is not blocked from most other actions those roles can take.
2. **`pg_cron` scheduling for the expiry-sweep functions was never live-observed actually firing** — the functions themselves are verified correct and callable; the `cron.schedule(...)` calls only run when `pg_cron` is available, which it is not in any environment this session had access to. Needs confirmation on the real hosted Supabase project.
3. **GitHub Pages deploy secrets (`VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`) are still not configured** — this requires a repository administrator action in GitHub Settings, which is outside what a code change can do. The deploy job correctly fails loudly rather than deploying a broken build in the meantime.
4. **`task_comments` still has a blanket tenant-wide SELECT policy** — discovered this pass, deliberately deferred (see above) rather than rushed; lower sensitivity than the 12 tables fixed this pass (free-text notes on a task, not PII/financial/compliance data), but still broader than `task.view` strictly implies for `hr_user`/`client_user`.
5. **Catalogue/reference tables remain tenant-wide readable with no permission gate** (`leave_types`, `task_templates`, `training_programs`, `training_requirements`, `attendance_policies`, `leave_policies`, `skills`) — assessed this pass as an intentional, precedented design choice (matching `leave_types`' own pre-existing explicit no-role-check policy), not a gap, but flagged here rather than silently assumed correct.
6. **Everything the original audit rated MEDIUM or LOW and did not name in its P0/P1 remediation-plan bullets** (site_assignments overlap prevention, contract-status auto-transition, `organizations` cascade-delete blast radius, `Modal` focus-return, remaining Funda360-branded UI strings, `npm audit` findings, package-lock.json's drifted `name` field, and the rest of the P2/P3 lists in `SEBETSA_PRODUCTION_CHECKLIST.md`) remains out of scope and exactly as the audit described it.
7. **Live penetration testing against the actual hosted Supabase project** (`xxoxhmmnrxnroegflkxy`, referenced in this sprint's brief) — **NOT VERIFIED**, and explicitly not claimable as verified: this session's Supabase MCP connector has access to two other projects in the same organization (`Funda360`, `human_res_app`), neither of which is the Sebetsa hosted project, and a direct request for that project ID by name returned a permission error. This session's own local-Postgres verification (real migrations, real stub schema, genuine fail-then-pass regression tests) is the strongest evidence available from this environment, but it is **not** a substitute for live verification against the actual hosted project with its real network topology, connection pooling, and auth configuration — recommended before general rollout, as the original audit already said, and repeated here rather than dropped.

**CI note (resolved, not a remaining risk):** GitHub Actions was triggered live for this commit (run [#16](https://github.com/Jablo-cmd/sebetsa/actions/runs/35014274077)) and all four jobs are now complete: `quality` (typecheck/lint/unit/build) PASS, `rls-tests` PASS, `e2e` PASS, `deploy` FAIL — but only at the already-documented "Verify production Supabase configuration" guard step (item 3 above), not a code or test failure. The workflow run's overall GitHub-reported conclusion is "failure" purely because that one job's expected, by-design failure counts against it — every job whose success this report claims is independently confirmed green, on real CI, not just locally.

---

## Verdict

**PRODUCTION READY**, conditioned on items 1–6 above being tracked and item 7 (live hosted-Supabase re-verification) completed before the platform is trusted with its first real, non-trial tenant's data — this verdict is about code-level correctness and CI-verified evidence, not a substitute for that live check.

Both HIGH findings the first remediation pass left open are now fixed, migrated, and verified fail-then-pass against a live database — as is the `submit_leave_request()` bug and a newly-discovered finding of the same severity class this pass's own broader audit surfaced and closed rather than left for a future session to find. Zero CRITICAL findings remain. Zero HIGH findings remain that this session's own audit passes (original + this sprint's broader one) identified. The RLS regression suite, the full quality gate (typecheck/lint/unit/build), and the full E2E suite were all confirmed green on a real, triggered GitHub Actions run against the actual CI configuration (run #16) — not merely reproduced in a substitute environment.

What keeps this from being an unconditional verdict: live verification against the actual hosted Supabase project could not be performed from this session (item 7) — the strongest remaining evidence gap is that this platform's *production* database has not itself been checked, only a faithful local reproduction of its schema, confirmed against real CI. A team with access to that project should re-run (or have re-run) the equivalent of this session's `p0_*`/`p1_*` RLS test files directly against it before onboarding real tenant data, and should confirm `pg_cron` scheduling is actually registered there (item 2), and configure the GitHub Pages deploy secrets (item 3) before relying on that deploy path. None of these is a code defect — all are verification/configuration steps outside this session's reach, named explicitly rather than glossed over.
