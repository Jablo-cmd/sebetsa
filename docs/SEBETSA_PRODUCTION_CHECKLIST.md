# Sebetsa Production Checklist

Practical go/no-go checklist derived from [`PRODUCTION_READINESS_AUDIT.md`](./PRODUCTION_READINESS_AUDIT.md) (audited 2026-09-15, `main` @ `74b957f`). Unchecked items are confirmed gaps, not unknowns — each maps to a finding in the audit report.

> **Remediation status (2026-09-15):** items below marked `[x] (remediated)` were fixed and verified in the P0/P1 remediation pass — see [`SEBETSA_REMEDIATION_REPORT.md`](./SEBETSA_REMEDIATION_REPORT.md) for the fix, the migration, and how it was verified. Everything else is still an open gap exactly as originally audited; the remediation report's "Remaining Risks" section calls out several of these by name as deliberately out of scope for that pass.

## Environment

- [ ] `.env.example` rewritten for Sebetsa (currently `VITE_APP_NAME=Funda360`, documents a nonexistent `admissions-public` function and a nonexistent `rls-tests/run.sh`, "per-school" language throughout)
- [x] No secrets committed to git (verified clean — anon key only, no service_role key in any client-reachable code)
- [ ] GitHub Actions secrets `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` configured in the `github-pages` environment (still missing — requires a repository-admin action in GitHub Settings, outside what a code change can do; the deploy job already fails loudly rather than deploying silently broken)
- [ ] `config.toml`'s `auto_expose_new_tables = true` reviewed/removed before it's deprecated upstream (2026-10-30) — low current risk since FORCE RLS is universal, but no safety net for a future migration that forgets an explicit grant

## Database

- [x] (remediated) Fix `employees_write_by_manager` RLS policy — the `hr_user` OR-branch has no tenant comparison (CRITICAL cross-tenant read/write/delete)
- [x] (remediated) Fix the 12+ blanket "any tenant member" SELECT policies (employees, teams, team_members, site_assignments, regions, clients, sites, contracts, contract_sites, departments, positions, shifts, shift_substitutions, shift_definitions, site_staffing_requirements, profiles) to actually check role, not just tenant
- [ ] Add cross-tenant FK-validation triggers to `clients`/`sites`/`contracts`/`contract_sites` (every other domain has this; org-hierarchy never got it) — still open, see remediation report
- [ ] Add cross-tenant FK-validation trigger to `asset_assignments` (the one relationship table missing it) — still open, see remediation report
- [ ] Decide and implement a tenant-deletion story (`organizations` cascades to `audit_log`/`incidents`/`compliance_records` with no soft-delete; `profiles.tenant_id` uniquely uses `SET NULL` instead of `CASCADE`)
- [ ] Add `employment_status`-transition validation trigger on `employees` (every other lifecycle table has one; this doesn't)
- [ ] Add overlap/exclusion constraint on `site_assignments` (shifts already have this pattern — reuse it)
- [ ] Fix `submit_leave_request()`'s missing `on conflict do nothing` upsert before the balance UPDATE (silently drops the "pending" figure on an employee's first-ever request) — still open, see remediation report
- [ ] Explicitly `revoke ... from public, anon` on the boolean permission-helper functions (`can_manage_profiles`, `can_assign_role`, `can_manage_org_structure`, `can_manage_operations`, `can_manage_employees`, `can_manage_leave`, `can_approve_leave`, `can_view_leave_broad`) — currently rely only on never being granted, not an explicit revoke
- [ ] Sanitize `p_file_name` in `create_contract_document_slot()` the same way `create_document_upload_slot()` already does
- [ ] Decide the fate of `sla_definitions.site_id IS NULL` (contract-wide SLA) — currently schema-supported but `compute_sla_measurement()` unconditionally rejects it

## Authentication

- [x] (remediated, partial — see below) MFA for platform_administrator/organization_administrator/hr_user now has real server-side enforcement, deliberately scoped to `admin_create_user`/`admin_update_user_role` only, not a blanket hard block on every action — see remediation report for why
- [x] Password reset/activation correctly forces session invalidation after password change
- [x] No secret exposure in session storage beyond standard supabase-js SPA behavior (no XSS sink exists to exploit it today)

## MFA

- [x] (remediated, partial) Server-side assurance-level check (`auth.jwt()->>'aal'`) added to the two highest-leverage privileged RPCs (user creation, role assignment) — not yet extended to every "required"-role sensitive RPC, tracked as a P2 follow-up in the remediation report
- [ ] Confirm the intended UX for a privileged user who never enrolls — currently indistinguishable from one who has

## RBAC

- [x] (remediated) Verify the fixed RBAC matrix (9 roles × 24 permission domains) against actual RLS after the CRITICAL policy fixes above — confirmed via the new `p0_tenant_rbac_remediation.sql` RLS test file
- [x] (remediated, partial) Self-action guards added to `approve_leave_request`/`reject_leave_request`/`revoke_leave_request`, `decide_attendance_correction`, `verify_task`, `verify_compliance_record`, `verify_incident_action` — **`verify_employee_qualification`/`verify_employee_skill` still have no guard**, explicitly open, see remediation report
- [x] (remediated) Corrected the `verify_compliance_record` migration comment that falsely claimed self-verification was already blocked

## RLS

- [x] (remediated) Restore `supabase/rls-tests/run.sh` so the test suite actually executes — 17/17 files now pass (verified via a native-Postgres equivalent in this sandbox; Docker itself was not re-verified, see remediation report)
- [ ] Add an RLS test file for `notifications` (none exists despite the service layer naming RLS as its enforcement mechanism)
- [x] (remediated) Add RLS test coverage for the actual self-verification scenario in `compliance_incidents.sql` (split into two correct assertions)
- [x] (remediated) Wire the RLS suite into the CI gate as a required check — the job now has a runner script to execute

## Multi-tenancy

- [ ] Re-verify all 7 attack scenarios (A–G) live against a real, hosted Supabase project — this remediation's verification was against a local from-scratch database with the real migrations applied, still not a live penetration test against the actual hosted project (see remediation report)
- [ ] Confirm platform-admin cross-tenant reads are acceptable as currently unaudited (no read-logging mechanism exists anywhere — only mutating RPCs write to `audit_log`)

## Storage

- [x] (remediated) Replicate the `employee_documents` medical/disciplinary sensitivity split at the `storage.objects` policy level, not just the metadata-table level
- [ ] Add magic-byte/content-sniffing validation for document uploads (self-acknowledged deferred gap; currently MIME/size only)
- [x] Storage paths are server-generated and filenames sanitized (employee-documents) — closes path traversal
- [ ] Apply the same filename-sanitization pattern to `create_contract_document_slot()` (see Database)

## Edge Functions

- [x] (remediated) `payments-initiate`/`payments-webhook` removed entirely (dead code referencing a nonexistent schema, not finished)
- [x] (remediated) `notifications-dispatch` removed entirely (dead code)
- [x] (remediated) Removed the whole Edge Function CI job, including the `admissions-public` reference (a file that never existed in this repo)

## Employees

- [x] (remediated) Make `terminate_employee()`'s `profiles.status='inactive'`/`employment_status='terminated'` actually mean something — added to `clock_in`, `submit_leave_request`, `request_attendance_correction`, `complete_task`
- [ ] Filter terminated employees out of scheduling/site-assignment candidate pickers (`searchEmployeeCandidates()` currently has no `employment_status` filter)
- [ ] Add employee uniqueness beyond `employee_number` (email or an ID-equivalent field)

## Sites

- [x] (remediated, partial) Added employee-`active` + site-`active` checks to open-ended `site_assignments` writes — contract-validity checks and overlap prevention are still open (see below)
- [ ] Add overlap prevention to `site_assignments`

## Scheduling

- [ ] Add a check that the scheduled employee holds a `site_assignments` row for that site
- [ ] Add an `employment_status` check to shift creation
- [ ] Decide whether recurring weekly `employee_availability` should become enforced (currently 100% advisory — no trigger reads it)
- [ ] Add E2E coverage — none currently exists for the scheduling/shift-creation flow at all

## Attendance

- [x] (remediated) Add `employment_status` check to `clock_in()` (via `employee_can_self_serve()`) — a `site_assignments` cross-check specifically was not added, still open
- [ ] Decide handling for clock-in during already-approved leave (currently silent, contradictory)
- [x] (remediated) Add self-approval guard to `decide_attendance_correction()`
- [ ] Add future-date validation to attendance corrections
- [ ] Decide whether `attendance_records_write_by_manager`'s direct-write escape hatch around the correction workflow is intentional or should be removed

## Leave

- [x] (remediated) Add self-approval guard to `approve_leave_request()`/`reject_leave_request()`/`revoke_leave_request()`
- [x] (remediated) Add a balance check to `approve_leave_request()` before allowing approval into negative
- [ ] Fix the first-request balance-recording bug (see Database) — still open, see remediation report
- [ ] Add overlapping-leave-request prevention

## Tasks

- [x] (remediated) Add a verifier-differs-from-completer check to `verify_task()`
- [ ] Add a `site_assignments` check to task assignment/reassignment

## Documents

- [x] (remediated) Fix the storage-layer sensitivity bypass (see Storage)
- [ ] Consider scheduling the expiry sweep instead of relying on someone opening the management page — sweep functions are now wired for `pg_cron` scheduling, but scheduling itself was never live-observed firing (`pg_cron` unavailable in this sandbox), see remediation report

## Incidents

- [ ] Consider an HR-sensitivity visibility split for incidents analogous to documents (currently any operational manager sees full incident detail)

## Compliance

- [x] (remediated) Add self-verification guard to `verify_compliance_record()` and correct the migration comment that falsely claims it's already blocked
- [x] (remediated, partial) `sync_expired_compliance_records()` (and qualifications/documents) now have tenant-batch wrappers wired for `pg_cron`; live scheduling itself unconfirmed, see remediation report

## Assets

- [ ] Add the missing cross-tenant validation trigger to `asset_assignments` — still open, see remediation report
- [ ] Consider a cross-site check on asset assignment

## Procurement

- [x] Self-approval already correctly blocked — use as the template for every other domain's approval RPC

## Training

- [ ] Decide whether expired required certifications should gate scheduling (currently `training_requirements` is never joined against `shifts` — fully decorative today)
- [ ] Add self-verification guard to `verify_employee_skill()`/`verify_employee_qualification()` — **still open, explicitly not fixed in this remediation pass**, see remediation report

## Reporting

- [x] Confirmed sound — `get_operational_metrics()` is correctly SECURITY INVOKER, RLS-riding by design; frontend calls the RPC directly, no client-side re-aggregation

## Notifications

- [ ] Add an RLS test file (none exists)
- [ ] Resolve the `notifications-dispatch` dead-code situation (see Edge Functions)
- [x] Core in-app notification RLS is maximally strict and verified clean (own-recipient-only)

## Mobile

- [ ] Enlarge the header menu-trigger, drawer-close, theme-toggle, and notification-bell touch targets to 44×44px (currently 32–36px)
- [ ] Enlarge the `Checkbox` hit target (currently 16×16px)
- [ ] Consider a card-collapse responsive pattern for admin-heavy tables (currently horizontal-scroll only, mitigated by a working scroll-affordance component)
- [x] Field-worker pages (`MyAttendancePage`, `MySchedulePage`) are already genuinely mobile-first — single-column, full-width buttons, offline/error states surfaced
- [x] Modal correctly constrains to viewport and scrolls internally — cannot overflow off-screen on a phone

## Accessibility

- [ ] Fix `Modal`'s missing return-focus-on-close behavior — affects nearly every create/edit/destructive workflow in the app (shared primitive)
- [x] Label association verified correct across sampled form primitives
- [x] Async status/error messaging correctly uses `role="alert"`
- [x] WCAG AA contrast fixes independently re-verified against actual token values — genuine, not just claimed
- [ ] Introduce a shared date-formatting utility (`src/lib/` has no `date.ts`; at least 8 files format dates independently with inconsistent locale handling)
- [ ] Fix the UTC-vs-SAST off-by-one risk in `AttendancePage.tsx`'s `todayIsoDate()` helper (uses `.toISOString()`, which returns the UTC date — wrong for ~2 hours nightly around SAST midnight)

## Backups

- [ ] Not assessed in this audit — no backup/retention policy documentation exists in the repo; confirm hosted Supabase project's backup configuration out-of-band

## Monitoring

- [ ] Not assessed in this audit — no monitoring/alerting configuration found in the repo

## Logging

- [ ] `audit_log` correctly captures every mutating privileged action with actor/target/timestamp/tenant, append-only, tamper-resistant
- [ ] Add read-side audit logging for platform-admin cross-tenant access (currently zero record of a platform admin merely browsing another tenant's data)

## Deployment

- [ ] Configure the GitHub Pages deploy job's missing `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` secrets — requires a repository-admin action in GitHub Settings; still open, cannot be done via a code change (the job already fails loudly rather than deploying broken)
- [x] (remediated) Fixed all three CI jobs that were failing on `main` (e2e, edge-functions, rls-tests) — see remediation report for exactly what each fix was

## Rollback

- [ ] Not assessed — no documented rollback procedure found in the repo

## Incident response

- [ ] Not assessed — no incident-response runbook found in the repo (the `FUNDA360_PRODUCTION_RUNBOOK.md` is Funda360-era and not applicable)

---

## Documentation cleanup (supporting, not blocking, but recommended before broad rollout)

- [ ] Rewrite `.env.example` for Sebetsa
- [ ] Write a genuine `SEBETSA-ARCHITECTURE.md` (currently zero Sebetsa-native architecture doc exists)
- [ ] Replace `docs/DOMAIN_STATUS.md` — it currently instructs a future session to resume building Funda360 school features
- [ ] Move `docs/funda360-reference-migrations/`, `docs/funda360-reference-other/`, `docs/product/`, and the 15 "FUNDA360 ACRONYM SPECIFICATION" documents out of the primary `docs/` tree (68% of `docs/` by size, actively misleading to a new contributor)
- [ ] Remove the 6+ user-facing Funda360 strings still shown to real users (`UsersPage.tsx`, `UserProfilePage.tsx`, `LoginForm.tsx`, `ForgotPasswordForm.tsx`, `MfaChallengePage.tsx`, `NotificationSettingsPage.tsx`, `dbErrors.ts`)
- [ ] Remove the orphaned `sendAccountActivationEmail()` dead function and its fabricated guardian-invitation comment
- [ ] Delete the empty `docs/adr/docs/FUNDA360_FUTURE_PRODUCT_VISION.md`

## Testing infrastructure (supporting, but a real production-risk driver)

- [x] (remediated) Deleted 24 e2e spec files testing functionality with no Sebetsa equivalent; migrated every remaining file off the broken `mockAuth`/`mockData` utilities to genuine `sebetsaAuth`/`sebetsaData` mocking — full suite now 127/127 passing
- [x] (remediated) The e2e job runs the full, now-passing suite unfiltered — no filtering flag was needed once every file was fixed rather than skipped
- [ ] Regenerate `package-lock.json` so its `name` field matches `package.json` (currently drifted to `"funda360"`)
- [ ] Address the 2 moderate (`react-router-dom` open-redirect + constructor-injection CVEs) and 2 low (`@supabase/auth-js` via an unusually old exact-pinned `supabase-js@2.45.4`) `npm audit` findings
