-- Corrective migration for 20260822000000_function_security_hardening.sql
--
-- That migration's search_path hardening (Part 1) worked correctly and is
-- confirmed still in effect (verified directly via pg_proc.proconfig on
-- all 49 functions in `public` immediately before writing this file — zero
-- remain unpinned). Its EXECUTE-privilege hardening (Part 2) did not take
-- effect: it ran `revoke execute on all functions in schema public from
-- anon`, but `anon` never held an individual grant to revoke. Every
-- function's actual ACL (re-verified directly via pg_proc.proacl this
-- session, not assumed) is
-- `{=X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
-- — the leading `=X/postgres` is Postgres's notation for a grant to the
-- PUBLIC pseudo-role, which anon (and every other role) inherits
-- regardless of anything revoked from anon specifically. Revoking from
-- anon when the grant lives on PUBLIC is a no-op, not an error, which is
-- exactly why the first migration applied cleanly but changed nothing on
-- this axis. No security regression resulted — the effective privilege
-- state after that migration was identical to before it, not worse.
--
-- This migration revokes from the actual holder of the grant (PUBLIC),
-- then explicitly restores exactly what each role needs:
--   - service_role keeps everything (trusted, RLS-bypassing backend role;
--     this hardening targets the anon/authenticated boundary, not
--     service_role's own already-elevated access).
--   - authenticated keeps the 19 RLS-policy-helper functions and the 8
--     admin RPCs the frontend calls directly (the same 27 functions
--     identified in the original investigation) — never the 22 trigger
--     functions.
--   - anon gets nothing, on any of the 49 functions.
--
-- It also corrects the "future functions" default-privilege gap for the
-- `postgres` grantor role: Supabase provisions every new project with its
-- own default-privilege entries (visible in pg_default_acl, not something
-- this project's own migrations ever created) granting
-- anon/authenticated/service_role EXECUTE automatically on any function
-- subsequently created by the `postgres` or `supabase_admin` role —
-- confirmed by direct query of pg_default_acl this session, showing
-- explicit per-role entries for both grantors, not a PUBLIC entry, which
-- is why the first migration's "revoke ... from public" default-privileges
-- statement was also a no-op (there was no PUBLIC default entry to
-- revoke). This migration removes anon's automatic default for the
-- `postgres` grantor. The equivalent statement for the `supabase_admin`
-- grantor was attempted and failed with a permission error (the role
-- running this migration is not a member of supabase_admin and cannot
-- alter its default privileges) — that statement was removed rather than
-- reattempted with a different workaround; it is a secondary, forward-
-- looking gap (governs only functions created in the future by a
-- supabase_admin-owned process, not any currently exploitable privilege)
-- and is reported as a known residual finding rather than solved here.
-- authenticated's and service_role's default access to future functions
-- is left as-is for both grantors — unlike anon, there is no reason to
-- force every future function through an extra opt-in step for those two,
-- and doing so wasn't part of what was found broken.

-- ---------------------------------------------------------------------------
-- Part 1: existing functions — revoke from the actual grant holder.
revoke execute on all functions in schema public from public;

-- Restore service_role's full access explicitly (identical to what it had
-- before this and the prior migration — nothing narrowed for it).
grant execute on all functions in schema public to service_role;

-- Category 1 — RLS policy helpers (19): authenticated must keep these.
grant execute on function public.current_tenant_id() to authenticated;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.is_learner_guardian(uuid) to authenticated;
grant execute on function public.is_teacher_of_enrolled_learner(uuid) to authenticated;
grant execute on function public.can_manage_school(uuid) to authenticated;
grant execute on function public.can_manage_profiles(uuid) to authenticated;
grant execute on function public.can_view_academic(uuid) to authenticated;
grant execute on function public.can_manage_academic(uuid) to authenticated;
grant execute on function public.can_view_employees(uuid) to authenticated;
grant execute on function public.can_manage_employees(uuid) to authenticated;
grant execute on function public.can_view_learners(uuid) to authenticated;
grant execute on function public.can_manage_learners(uuid) to authenticated;
grant execute on function public.can_view_learner_medical(uuid) to authenticated;
grant execute on function public.can_manage_learner_medical(uuid) to authenticated;
grant execute on function public.can_record_attendance(uuid, uuid) to authenticated;
grant execute on function public.can_manage_assessment(uuid, uuid) to authenticated;
grant execute on function public.can_manage_assessment_result(uuid, uuid) to authenticated;
grant execute on function public.can_assign_role(public.user_role, public.user_role) to authenticated;
grant execute on function public.can_assign_employee_role(public.user_role) to authenticated;

-- Category 3 — admin RPCs the frontend calls directly (8): authenticated
-- must keep these.
grant execute on function public.admin_create_user(text, text, text, text, public.user_role, uuid) to authenticated;
grant execute on function public.admin_update_user_role(uuid, public.user_role) to authenticated;
grant execute on function public.provision_employee_login(uuid, public.user_role, text) to authenticated;
grant execute on function public.terminate_employee(uuid, date) to authenticated;
grant execute on function public.reactivate_employee(uuid) to authenticated;
grant execute on function public.promote_learner(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.change_learner_status(uuid, public.learner_status, text) to authenticated;
grant execute on function public.set_active_academic_year(uuid) to authenticated;

-- Category 2 (all 22 trigger functions) intentionally receives no
-- authenticated grant here, same as the first migration's intent — this
-- corrective migration changes *how* the revoke works, not which
-- functions end up accessible to which role.

-- ---------------------------------------------------------------------------
-- Part 2: future functions — close anon's automatic default access for the
-- `postgres` grantor role (confirmed via pg_default_acl). The equivalent
-- statement for the `supabase_admin` grantor is intentionally omitted —
-- the role executing this migration lacks permission to alter it; see the
-- header comment. Tracked as a residual, secondary finding, not silently
-- dropped.
alter default privileges for role postgres in schema public revoke execute on functions from anon;
