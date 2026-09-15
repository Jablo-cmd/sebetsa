# Sebetsa Production Checklist

Practical go/no-go checklist derived from [`PRODUCTION_READINESS_AUDIT.md`](./PRODUCTION_READINESS_AUDIT.md) (audited 2026-09-15, `main` @ `74b957f`). Unchecked items are confirmed gaps, not unknowns — each maps to a finding in the audit report.

## Environment

- [ ] `.env.example` rewritten for Sebetsa (currently `VITE_APP_NAME=Funda360`, documents a nonexistent `admissions-public` function and a nonexistent `rls-tests/run.sh`, "per-school" language throughout)
- [x] No secrets committed to git (verified clean — anon key only, no service_role key in any client-reachable code)
- [ ] GitHub Actions secrets `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` configured in the `github-pages` environment (currently missing — deploy job fails)
- [ ] `config.toml`'s `auto_expose_new_tables = true` reviewed/removed before it's deprecated upstream (2026-10-30) — low current risk since FORCE RLS is universal, but no safety net for a future migration that forgets an explicit grant

## Database

- [ ] Fix `employees_write_by_manager` RLS policy — the `hr_user` OR-branch has no tenant comparison (CRITICAL cross-tenant read/write/delete)
- [ ] Fix the 12+ blanket "any tenant member" SELECT policies (employees, teams, team_members, site_assignments, regions, clients, sites, contracts, contract_sites, departments, positions, shifts, shift_substitutions, shift_definitions, site_staffing_requirements, profiles) to actually check role, not just tenant
- [ ] Add cross-tenant FK-validation triggers to `clients`/`sites`/`contracts`/`contract_sites` (every other domain has this; org-hierarchy never got it)
- [ ] Add cross-tenant FK-validation trigger to `asset_assignments` (the one relationship table missing it)
- [ ] Decide and implement a tenant-deletion story (`organizations` cascades to `audit_log`/`incidents`/`compliance_records` with no soft-delete; `profiles.tenant_id` uniquely uses `SET NULL` instead of `CASCADE`)
- [ ] Add `employment_status`-transition validation trigger on `employees` (every other lifecycle table has one; this doesn't)
- [ ] Add overlap/exclusion constraint on `site_assignments` (shifts already have this pattern — reuse it)
- [ ] Fix `submit_leave_request()`'s missing `on conflict do nothing` upsert before the balance UPDATE (silently drops the "pending" figure on an employee's first-ever request)
- [ ] Explicitly `revoke ... from public, anon` on the boolean permission-helper functions (`can_manage_profiles`, `can_assign_role`, `can_manage_org_structure`, `can_manage_operations`, `can_manage_employees`, `can_manage_leave`, `can_approve_leave`, `can_view_leave_broad`) — currently rely only on never being granted, not an explicit revoke
- [ ] Sanitize `p_file_name` in `create_contract_document_slot()` the same way `create_document_upload_slot()` already does
- [ ] Decide the fate of `sla_definitions.site_id IS NULL` (contract-wide SLA) — currently schema-supported but `compute_sla_measurement()` unconditionally rejects it

## Authentication

- [ ] Decide whether MFA for platform_administrator/organization_administrator/hr_user should be a hard block, not a dismissible banner — currently zero server-side enforcement (no `aal` check anywhere in RLS/RPCs)
- [x] Password reset/activation correctly forces session invalidation after password change
- [x] No secret exposure in session storage beyond standard supabase-js SPA behavior (no XSS sink exists to exploit it today)

## MFA

- [ ] Add a server-side assurance-level check (`auth.jwt()->>'aal'`) to at least the "required" roles' most sensitive RPCs, or accept and document that MFA is advisory-only for now
- [ ] Confirm the intended UX for a privileged user who never enrolls — currently indistinguishable from one who has

## RBAC

- [ ] Verify the fixed RBAC matrix (9 roles × 24 permission domains) against actual RLS after the CRITICAL policy fixes above — the frontend `RequirePermission` guard is already consistent with `rolePermissions.ts`, but RLS is the real boundary and two of its policies currently disagree with it
- [ ] Add self-action guards (`if v_subject = auth.uid() and not is_platform_admin() then raise exception ...`) to: `approve_leave_request`/`reject_leave_request`, `decide_attendance_correction`, `verify_task`, `verify_compliance_record`, `verify_incident_action`, `verify_employee_qualification`/`verify_employee_skill` — `decide_procurement_request` already does this correctly; replicate its pattern
- [ ] Correct or remove the `verify_compliance_record` migration comment that falsely claims self-verification is already blocked

## RLS

- [ ] Restore or rewrite `supabase/rls-tests/run.sh` so the 13 existing, genuinely thorough test files actually execute (currently referenced by CI but absent — job fails instantly, exit 127)
- [ ] Add an RLS test file for `notifications` (none exists despite the service layer naming RLS as its enforcement mechanism)
- [ ] Add RLS test coverage for the actual self-verification scenario in `compliance_incidents.sql` (current test only proves role-tier gating, not same-person gating)
- [ ] Wire the RLS suite into the CI gate as a required check before merge, once it runs

## Multi-tenancy

- [ ] Re-verify all 7 attack scenarios (A–G) live against a real Supabase project once the CRITICAL policy fixes land — this audit's verification was static (SQL trace), not a live penetration test
- [ ] Confirm platform-admin cross-tenant reads are acceptable as currently unaudited (no read-logging mechanism exists anywhere — only mutating RPCs write to `audit_log`)

## Storage

- [ ] Replicate the `employee_documents` medical/disciplinary sensitivity split at the `storage.objects` policy level, not just the metadata-table level (`operations_manager` can currently bypass it via the Storage API directly)
- [ ] Add magic-byte/content-sniffing validation for document uploads (self-acknowledged deferred gap; currently MIME/size only)
- [x] Storage paths are server-generated and filenames sanitized (employee-documents) — closes path traversal
- [ ] Apply the same filename-sanitization pattern to `create_contract_document_slot()` (see Database)

## Edge Functions

- [ ] Decide the fate of `payments-initiate`/`payments-webhook`: either finish the port (add the missing `payment_intents`/`payment_gateway_configs`/`settle_payment_intent`, fix the 3 defects below) or remove them from the deployed function set and CI
- [ ] If keeping payments: fix `payments-initiate`'s raw-exception-text leak to callers, implement the described-but-missing settlement safety net (signature-gate enforcement, amount re-check, idempotency via a unique `provider_event_id` constraint), and scope CORS away from `*`
- [ ] Decide the fate of `notifications-dispatch`: either implement the missing `notification_deliveries` outbox table/enqueue path or remove it from CI and deployment
- [ ] Remove `admissions-public` from `ci.yml`'s Deno typecheck step (references a file that doesn't exist in this repo)

## Employees

- [ ] Make `terminate_employee()`'s `profiles.status='inactive'` actually mean something — add the check to every self-service RPC (`clock_in`, `submit_leave_request`, `request_attendance_correction`, `complete_task`, availability writes) or, better, deny at the RLS/session layer
- [ ] Filter terminated employees out of scheduling/site-assignment candidate pickers (`searchEmployeeCandidates()` currently has no `employment_status` filter)
- [ ] Add employee uniqueness beyond `employee_number` (email or an ID-equivalent field)

## Sites

- [ ] Add employee-`active` + site-`active` + contract-validity checks to `site_assignments` writes
- [ ] Add overlap prevention to `site_assignments`

## Scheduling

- [ ] Add a check that the scheduled employee holds a `site_assignments` row for that site
- [ ] Add an `employment_status` check to shift creation
- [ ] Decide whether recurring weekly `employee_availability` should become enforced (currently 100% advisory — no trigger reads it)
- [ ] Add E2E coverage — none currently exists for the scheduling/shift-creation flow at all

## Attendance

- [ ] Add `employment_status` + `site_assignments` checks to `clock_in()`
- [ ] Decide handling for clock-in during already-approved leave (currently silent, contradictory)
- [ ] Add self-approval guard to `decide_attendance_correction()`
- [ ] Add future-date validation to attendance corrections
- [ ] Decide whether `attendance_records_write_by_manager`'s direct-write escape hatch around the correction workflow is intentional or should be removed

## Leave

- [ ] Add self-approval guard to `approve_leave_request()`/`reject_leave_request()`/`revoke_leave_request()`
- [ ] Add a balance check to `approve_leave_request()` before allowing approval into negative
- [ ] Fix the first-request balance-recording bug (see Database)
- [ ] Add overlapping-leave-request prevention

## Tasks

- [ ] Add a verifier-differs-from-completer check to `verify_task()`
- [ ] Add a `site_assignments` check to task assignment/reassignment

## Documents

- [ ] Fix the storage-layer sensitivity bypass (see Storage)
- [ ] Consider scheduling the expiry sweep instead of relying on someone opening the management page

## Incidents

- [ ] Consider an HR-sensitivity visibility split for incidents analogous to documents (currently any operational manager sees full incident detail)

## Compliance

- [ ] Add self-verification guard to `verify_compliance_record()` and correct the migration comment that falsely claims it's already blocked
- [ ] Wire `sync_expired_compliance_records()` into the frontend (currently fully implemented but never called — expired records show as compliant indefinitely)

## Assets

- [ ] Add the missing cross-tenant validation trigger to `asset_assignments`
- [ ] Consider a cross-site check on asset assignment

## Procurement

- [x] Self-approval already correctly blocked — use as the template for every other domain's approval RPC

## Training

- [ ] Decide whether expired required certifications should gate scheduling (currently `training_requirements` is never joined against `shifts` — fully decorative today)
- [ ] Add self-verification guard to `verify_employee_skill()`/`verify_employee_qualification()`

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

- [ ] Fix the GitHub Pages deploy job (missing `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` secrets)
- [ ] Remove or fix the three CI jobs currently failing on `main` (e2e, edge-functions, rls-tests) before treating CI green as meaningful again

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

- [ ] Filter or delete the ~40 e2e spec files using the broken `mockAuth`/`mockData` utilities (wrong localStorage key, references routes that don't exist)
- [ ] Once filtered, wire the remaining genuine spec files into a required CI check
- [ ] Regenerate `package-lock.json` so its `name` field matches `package.json` (currently drifted to `"funda360"`)
- [ ] Address the 2 moderate (`react-router-dom` open-redirect + constructor-injection CVEs) and 2 low (`@supabase/auth-js` via an unusually old exact-pinned `supabase-js@2.45.4`) `npm audit` findings
