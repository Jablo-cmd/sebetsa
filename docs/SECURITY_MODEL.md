# Sebetsa security model

What the database enforces, how it is verified, and what is *not* covered. Everything marked **verified** is exercised by a suite in `supabase/rls-tests/tests/` that runs on every CI build against a throwaway PostgreSQL built from `supabase/migrations`. Nothing here has been verified against a live hosted Supabase project — see [DOMAIN_STATUS.md](./DOMAIN_STATUS.md).

## 1. Tenant isolation

- Every table in `public` has row-level security **and** `FORCE ROW LEVEL SECURITY` (suite `security_catalog` fails if a new table lacks either).
- Tenant tables are filtered by `tenant_id = current_tenant_id()`. `current_tenant_id()` returns a tenant only for an **active** profile, so a deactivated account loses access in the database itself, not just in the UI.
- `anon` holds no privileges on any table and cannot execute any function in `public`; objects created by future migrations start closed to `anon`/`PUBLIC`.
- `authenticated` has no `TRUNCATE`, `REFERENCES` or `TRIGGER` rights, and cannot write the audit, outbox, scope or separation-of-duties tables directly.
- Cross-tenant references (a record in tenant A pointing at tenant B's site, contract, employee…) are rejected by `validate_*_ref` triggers; contract↔site links are additionally bound to one client.

## 2. Roles and scope

Tenant-wide roles (platform administrator, organisation administrator, operations manager, HR, employee, client user) see their tenant. **Regional managers, site managers and supervisors are scoped**: they reach site-bound operational records only inside a region, site or team assigned in `user_scopes`.

- Eight tables carry a `RESTRICTIVE` scope policy: `shifts`, `attendance_records`, `tasks`, `incidents`, `compliance_records`, `assets`, `inventory_movements`, `procurement_requests`. Policies combine with `AND`, so scope can only narrow access.
- **Fail closed:** a scoped role with no scope assigned sees none of those records. The user page warns when this is the case.
- Scopes are granted and revoked only through `grant_user_scope()` / `revoke_user_scope()` (organisation structure managers; audited; the grantee cannot be the granter — rule `scope.assign`). The UI is on a scoped user's profile page (`/users/:id`).
- A region scope covers the sites in that region; a team scope covers the team's site.
- **Verified:** `enterprise_security`, `security_hardening`, `create_task` (a scoped manager cannot create a task outside their scope).

## 3. Separation of duties

A single mechanism: the `sod_rules` table, `assert_separation_of_duties(rule, subjects[])` and `AFTER UPDATE` guard triggers on the workflow tables, so a rule holds whether the change goes through an RPC or a direct update. Thirteen rules:

| Rule | Meaning |
| ---- | ------- |
| `leave.decide` | The employee a leave request concerns cannot approve, reject or revoke it. |
| `attendance_correction.decide` | The requester, or the employee corrected, cannot decide the correction. |
| `task.verify` | The person who completed a task, or its assignee, cannot verify it. |
| `incident.close` | The reporter cannot close the incident. |
| `incident_action.verify` | The action's owner cannot verify it. |
| `compliance.verify` | The person responsible for a record cannot verify it. |
| `document.verify` | The uploader, or the employee the document belongs to, cannot verify or reject it. |
| `procurement.decide` | The requester cannot approve or reject their own request. |
| `skill.verify`, `qualification.verify` | An employee cannot verify their own skill or qualification. |
| `role.assign` | A user cannot change their own role. |
| `scope.assign` | A user cannot grant themselves a scope. |
| `user.status` | A user cannot activate or deactivate their own account. |

The suite asserts that all thirteen rules are installed and that the guards exist; individual suites exercise the refusals.

## 4. Audit

- `audit_log` is **append-only**: `UPDATE`, `DELETE` and `TRUNCATE` raise `audit_log_immutable`. Rows are written only by `write_audit_log()` / `write_security_audit_event()` (`SECURITY DEFINER`, not executable by `authenticated`).
- Each row has a `category` (`business` or `security`), an `outcome`, a `request_id` taken from the request headers when present, and `metadata`. Actions beginning `role_`, `user_`, `tenant_`, `login_`, `mfa_`, `permission_`, `scope_`, `provision`, and everything on `user_scopes`, are classified **security**; the rest are **business**.
- **Retention:** `purge_audit_log(interval)` is `service_role` only and refuses any window shorter than 365 days; the default is 7 years. It is *defined*, not *scheduled* — scheduling it is a deployment task.
- **Read access:** an organisation's `audit_log` rows are readable by its organisation administrators and platform administrators only.
- Audit rows never carry credentials: payloads are row snapshots of workflow tables, and the worker logs counts, not destinations or bodies.

## 5. Privileged functions

- All 96 `SECURITY DEFINER` functions pin `search_path` (asserted by `security_catalog`). Where a function needs `pgcrypto` the pinned path includes `extensions`, as on hosted Supabase.
- Internal helpers (`assert_separation_of_duties`, `employee_profile_id`, `compute_attendance_metrics`, `purge_audit_log`, `write_security_audit_event`, the enqueue/validate triggers) are not executable by `authenticated`.
- `claim_notification_deliveries` is executable by `service_role` only.
- Server-derived authorship: `created_by`, `recorded_by`, `author_id`, `submitted_by`, `performed_by` are set by trigger from the caller, never from the request body.
- Functions that can run as the caller (`create_task`, `set_contract_sites`) are `SECURITY INVOKER` so every policy still applies to them.

## 6. Accounts, sessions, MFA

- Deactivation (`admin_set_user_status`) bans the auth user and flips the profile status; reactivation reverses both. A user cannot change their own status.
- `profiles` updates are limited to contact fields (`first_name`, `last_name`, `phone`, `avatar_url`); role, tenant, status and email change only through controlled RPCs.
- TOTP MFA enrolment and challenge are implemented, and a banner asks privileged roles to enrol.
- **MFA is enforced server-side.** For platform administrators, organisation administrators, operations managers and HR users (and anyone who has enrolled a factor) the database refuses every tenant-scoped read, write and RPC unless the session is `aal2`, through `current_tenant_id()` / `is_platform_admin()`. See [MFA.md](./MFA.md) for the design, enrolment, recovery and verification status. Tested locally and in CI; not live-verified.
- **Fail-closed helpers.** Permission helpers return `false`, never `NULL`, so definer RPCs cannot fail open.
- Password policy, breached-password checks, rate limiting and session lifetimes are Supabase Auth settings and must be confirmed in the hosted project.

## 7. Files

- Employee and contract documents live in private buckets; the app opens them with 5-minute signed URLs and never stores a public link.
- Upload is two-step (database slot, then bytes). A failed upload cancels its slot (`cancel_document_upload`, `cancel_contract_document_upload`) so no record points at a missing file; once the file exists the record cannot be cancelled.
- Allowed types and size limits are validated in the database function, not only in the browser.

## 8. Browser and bundle

- The browser holds only the anon key. CI refuses to deploy a bundle that contains `service_role` strings.
- Dependency audit runs in CI (`npm audit --omit=dev --audit-level=high`).
- **Runtime dependencies: 0 known advisories** (`npm audit --omit=dev`). `@supabase/supabase-js` was upgraded 2.45.4 → 2.117.2, which clears the two `@supabase/auth-js` advisories (GHSA-8r88-6cj9-9fh5, malformed-input path routing); `react-router` is on v7 (7.18.4). The upgrade tightened the client's generated typings; the eight resulting call sites were typed properly (no casts), and typecheck, lint, unit tests, build and the full E2E suite were rerun.
- **Remaining advisories are build/test tooling only (13: 2 critical, 6 high, 5 moderate); none ships in the browser bundle.** Each needs a major-version jump that was deliberately not taken in a security-closure pass:

  | Package | Advisory class | Needs | Exposure |
  | ------- | -------------- | ----- | -------- |
  | `vitest` / `tinypool` (critical) | prototype-pollution gadget in worker options → RCE | vitest 5 | Test runner executing only this repository's code in CI and locally; not reachable from user input or production |
  | `vite` / `esbuild` (high/moderate) | any website can send requests to the **dev server** and read responses | vite 8 | Development server only; do not browse untrusted sites while `npm run dev` is running |
  | `tailwindcss` → `braces`, `micromatch`, `chokidar`, `fast-glob`, `postcss-*` (high/moderate) | ReDoS / CPU exhaustion in glob and selector parsing | tailwindcss 4 | Build time over trusted source files |

  Follow-up (tracked in the roadmap): move to vite 8 / vitest 5 / tailwind 4 in a dedicated branch with the full gate, then re-run the audit.

## 10. CI/CD security

- **Actions are pinned to commit SHAs** (all seven distinct actions in `.github/workflows/`, each annotated with its version, resolved from the upstream tags with `git ls-remote`). Dependabot (`github-actions` ecosystem, weekly) raises the bump PRs, so pins stay current.
- **Minimal token permissions:** workflow default `contents: read`; only the deploy job adds `pages: write` and `id-token: write`; `uptime.yml` declares `permissions: {}`. Every checkout uses `persist-credentials: false`.
- **Secrets:** the only secrets are the public anon-key build variables and the optional `OPS_HEALTH_SECRET`; none is exposed to jobs that run pull-request code. There is no `pull_request_target` trigger, so a fork's pull request runs with a read-only token and no secrets. The bundle is scanned for `service_role` strings before deploy.
- **Release gate and deploy:** quality → edge functions → RLS → E2E → release-gate; deploy runs only for a push to `main` after the gate, in the `github-pages` environment. `workflow_dispatch` runs every gate on any branch but never deploys.
- **Not verifiable from the repository:** branch protection / required checks and environment reviewers are GitHub settings. They are **not confirmed**; configure `main` to require the release-gate check and reviews.

## 9. Not covered

- Live verification of any of the above on the hosted project.
- Provider webhooks against real providers: the signed, replay-protected, idempotent receipt endpoint exists and is tested against reference vectors, but has never received live Resend/Twilio traffic.
- Live verification of MFA settings, per-user time zones for quiet hours, and automated anomaly alerting.
