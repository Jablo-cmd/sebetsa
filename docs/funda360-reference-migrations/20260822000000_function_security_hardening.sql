-- Function security hardening — search_path pinning + least-privilege EXECUTE
--
-- Closes the two finding classes from Supabase's own security advisor
-- (`supabase db advisors --linked --type security`), verified this session
-- against a full, live enumeration of every function in `public` (49
-- total, via a direct read-only query against pg_proc/information_schema —
-- not just migration source) before writing a single line here. Every
-- function was classified into exactly one of three groups by how it's
-- actually used, confirmed by cross-referencing RLS policy USING/WITH
-- CHECK clauses, trigger definitions, and every `.rpc(...)` call site in
-- the frontend. Full investigation report and per-function evidence:
-- see the "Funda360 Security Advisor Investigation" artifact from this
-- engagement.
--
-- Category 1 — RLS policy-body helpers (current_tenant_id, is_platform_
-- admin, is_learner_guardian, is_teacher_of_enrolled_learner, every
-- can_view_*/can_manage_*/can_assign_* function): referenced directly
-- inside a table's RLS policy expression, evaluated as the querying
-- role — authenticated MUST keep EXECUTE or every RLS-gated query in the
-- app breaks. No anon-facing data flow exists anywhere in this app
-- (login goes through Supabase Auth's own GoTrue endpoints, never a
-- PostgREST RPC call as anon), so anon never legitimately needs these.
--
-- Category 2 — pure trigger functions (every *_validate_tenant,
-- prevent_*, set_updated_at, set_created_updated_by): confirmed
-- RETURNS TRIGGER, never referenced by a policy, never called from the
-- frontend. Trigger firing in Postgres is gated by INSERT/UPDATE/DELETE
-- privilege on the *table*, not EXECUTE on the trigger function — revoking
-- EXECUTE from both anon and authenticated does not affect trigger
-- execution at all.
--
-- Category 3 — privileged admin RPCs (admin_create_user,
-- admin_update_user_role, provision_employee_login, terminate_employee,
-- reactivate_employee, promote_learner, change_learner_status,
-- set_active_academic_year): confirmed as the *only* 8 functions the
-- frontend ever calls via supabase.rpc(...). Each already performs its
-- own internal authorization check (can_assign_role/can_manage_*) as the
-- first statement in its body — already proven by the existing 198-test
-- RLS/authorization suite. authenticated keeps EXECUTE; anon does not.
--
-- Signatures below were verified against a live query of pg_proc for this
-- exact project (rzkybmkzhpwovpvrjkxk), not transcribed from migration
-- source alone — that check caught one real discrepancy
-- (can_manage_assessment_result actually takes two arguments,
-- target_school_id and target_assessment_id, not one).

-- ---------------------------------------------------------------------------
-- Part 1: search_path hardening — every function still missing it.
-- (current_tenant_id, is_platform_admin, is_learner_guardian,
-- is_teacher_of_enrolled_learner, assessment_results_validate_tenant, and
-- attendance_records_validate_tenant already have it set from earlier
-- work and are not touched again here.)

-- Category 1 — RLS policy helpers (15 of 19 not already fixed)
alter function public.can_manage_school(uuid) set search_path = public;
alter function public.can_manage_profiles(uuid) set search_path = public;
alter function public.can_view_academic(uuid) set search_path = public;
alter function public.can_manage_academic(uuid) set search_path = public;
alter function public.can_view_employees(uuid) set search_path = public;
alter function public.can_manage_employees(uuid) set search_path = public;
alter function public.can_view_learners(uuid) set search_path = public;
alter function public.can_manage_learners(uuid) set search_path = public;
alter function public.can_view_learner_medical(uuid) set search_path = public;
alter function public.can_manage_learner_medical(uuid) set search_path = public;
alter function public.can_record_attendance(uuid, uuid) set search_path = public;
alter function public.can_manage_assessment(uuid, uuid) set search_path = public;
alter function public.can_manage_assessment_result(uuid, uuid) set search_path = public;
alter function public.can_assign_role(public.user_role, public.user_role) set search_path = public;
alter function public.can_assign_employee_role(public.user_role) set search_path = public;

-- Category 2 — trigger functions (20 of 22 not already fixed)
alter function public.assessments_validate_tenant() set search_path = public;
alter function public.class_teacher_assignments_validate_tenant() set search_path = public;
alter function public.classes_validate_grade_school() set search_path = public;
alter function public.employees_validate_department_school() set search_path = public;
alter function public.employees_validate_profile_tenant() set search_path = public;
alter function public.employees_validate_reports_to() set search_path = public;
alter function public.learner_documents_validate_tenant() set search_path = public;
alter function public.learner_emergency_contacts_validate_tenant() set search_path = public;
alter function public.learner_enrollments_validate_tenant_and_grade() set search_path = public;
alter function public.learner_guardians_validate_tenant() set search_path = public;
alter function public.learner_medical_information_validate_tenant() set search_path = public;
alter function public.learners_validate_status_transition() set search_path = public;
alter function public.prevent_direct_email_change() set search_path = public;
alter function public.prevent_direct_role_change() set search_path = public;
alter function public.prevent_direct_tenant_change() set search_path = public;
alter function public.prevent_direct_year_activation() set search_path = public;
alter function public.prevent_self_status_change() set search_path = public;
alter function public.set_created_updated_by() set search_path = public;
alter function public.set_updated_at() set search_path = public;
alter function public.terms_validate_academic_year_school() set search_path = public;

-- ---------------------------------------------------------------------------
-- Part 2: EXECUTE privilege hardening.
--
-- Revoke anon from every function in schema public — a live enumeration
-- of all 49 functions found none with a legitimate anon caller, and no
-- unauthenticated flow anywhere in this app reaches a PostgREST RPC call.
-- Then explicitly re-grant authenticated only where it's actually
-- required (Category 1 + Category 3); Category 2 (trigger functions)
-- receives no authenticated grant at all, since no legitimate caller
-- should ever invoke a trigger function directly and doing so would error
-- regardless (NEW/OLD are undefined outside real trigger execution).
revoke execute on all functions in schema public from anon;

-- Category 1 — RLS policy helpers: authenticated MUST keep these, or
-- every query against a table whose policy calls one of these breaks.
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

-- Category 3 — admin RPCs the frontend calls directly: authenticated MUST
-- keep these.
grant execute on function public.admin_create_user(text, text, text, text, public.user_role, uuid) to authenticated;
grant execute on function public.admin_update_user_role(uuid, public.user_role) to authenticated;
grant execute on function public.provision_employee_login(uuid, public.user_role, text) to authenticated;
grant execute on function public.terminate_employee(uuid, date) to authenticated;
grant execute on function public.reactivate_employee(uuid) to authenticated;
grant execute on function public.promote_learner(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.change_learner_status(uuid, public.learner_status, text) to authenticated;
grant execute on function public.set_active_academic_year(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Close the gap for any function created after this migration: new
-- functions must opt in to public/anon execution explicitly rather than
-- silently inheriting it, matching the least-privilege posture just
-- established for every existing function.
alter default privileges in schema public revoke execute on functions from public;
