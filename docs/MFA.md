# Multi-factor authentication (server-side enforcement)

MFA is enforced **in the database**, not only in the browser. A client that skips the UI, calls PostgREST or an RPC directly, or replays an `aal1` token gets nothing from a role that must use MFA.

## What is enforced

`public.mfa_satisfied()` is true when any of these holds:

| Condition | Result |
| --------- | ------ |
| The JWT `aal` claim is `aal2` | satisfied |
| No authenticated user (service role, internal jobs) | satisfied (those paths have their own controls) |
| `security_settings.mfa_enforced = false` (operator break-glass, see below) | satisfied |
| The role is in `public.mfa_roles()` (platform administrator, organisation administrator, operations manager, HR user) and the token is not `aal2` | **not satisfied** |
| The user has a verified `auth.mfa_factors` row and the token is not `aal2` | **not satisfied** (anyone who enrolled gets the protection) |
| Otherwise (no factor, role not required) | satisfied |

`current_tenant_id()` and `is_platform_admin()` both require `mfa_satisfied()`. Every permission helper (`can_manage_*`, `can_approve_leave`, `can_view_leave_broad`, `can_access_site`, scope and audit policies) resolves the caller through those two functions, so there is **one choke point**: below `aal2` a required-role session has no tenant and no platform-admin status, and every tenant-scoped read, write and RPC is refused. Only the caller's own profile row and own notifications stay readable, so the app can still route the user to enrolment.

Deactivated users stay blocked regardless of `aal` (`current_tenant_id()` still requires an active profile).

### Fail-closed helpers

The permission helpers used to return `NULL` (not `false`) when the caller had no tenant. Policies treat `NULL` as deny, but `SECURITY DEFINER` RPCs written `if not can_x(...) then raise` do **not** raise on `NULL`, so they ran. The migration wraps every such helper in `coalesce(..., false)`. The suite asserts the helpers return `false`, never `NULL`.

### hr_user carve-out

The original `employees` / `departments` / `positions` write policies allowed `role = 'hr_user'` with no tenant and no MFA check. They are now bound to `current_tenant_id()`. Found by the MFA suite.

## Enrolment

Enrolment and challenge are GoTrue operations and work at `aal1`, so a required-role user with no factor can always enrol:

1. Sign in with a password (`aal1`).
2. `ProtectedRoute` sees a required role with no verified factor and redirects to `/mfa-setup`, a page outside the tenant gate that needs only the auth session.
3. The user scans the QR code and verifies a code; GoTrue promotes the session to `aal2`.
4. The page reloads, so profile and tenant are fetched again with the `aal2` token.

A user who has a factor but signed in with only a password is held at `/mfa-challenge` until the code is entered.

A required role cannot remove its factor from My Profile (the database would lock it out); GoTrue also requires `aal2` to unenrol.

## Recovery

- **Lost authenticator, user cannot sign in:** an administrator who is themselves `aal2` cannot remove another user's factor from the app. Recovery is an operator action in the Supabase dashboard (Authentication → Users → the user → remove the MFA factor), after the organisation verifies the person out of band. The user then re-enrols at next sign-in. Record the event in the security log.
- **Every administrator is locked out / enrolment outage:** the operator sets `security_settings.mfa_enforced = false` with direct database or service-role access, fixes the problem, then sets it back to `true`. There is no client grant on that table, and flipping it must be treated as a security event (ticket, two people, time-boxed). This is the only way to relax enforcement and it is not reachable from the browser or the API.
- **Privilege escalation:** nobody can grant themselves a role, a scope or MFA status through the app (`role.assign`, `scope.assign` separation-of-duties rules). Enrolment status comes from `auth.mfa_factors`, which no `public` API writes.

## Verification

| Where | What | Status |
| ----- | ---- | ------ |
| `supabase/rls-tests/tests/mfa_enforcement.test.sql` | Each required role at `aal1` and with no `aal` claim: zero rows from tenant tables, helpers return `false`, RPCs (`grant_user_scope`, `create_task`, …) refused; `aal2` allowed; optional role without a factor allowed; optional role with a factor at `aal1` denied; deactivated user stays blocked at `aal2`; direct RPC cannot bypass; `mfa_enforced=false` switch | Local (PG16) and CI |
| `e2e/mfa.spec.ts` | Forced enrolment for all four roles, wrong/right code, challenge, no way to remove a required factor, optional roles unaffected. The fake backend mirrors `mfa_satisfied()`. | Local and CI |
| Live Supabase project | `aal` claim present in issued JWTs, Auth MFA (TOTP) enabled, `security_settings` row present, migration applied | **NOT VERIFIED** — needs the live project |

Until the last row is checked against the hosted project, MFA is **implemented and tested against a local database, not live-verified**.

## Operating notes

- TOTP MFA must be enabled in Supabase Auth settings; the `aal` claim then appears in access tokens.
- `mfa_roles()` and `src/features/rbac/constants/mfaRequiredRoles.ts` must stay identical; change both together.
- Existing tokens issued before enrolment stay `aal1` until the user verifies; after the migration, privileged users are asked to enrol at their next page load. Announce the rollout before applying it to production.
