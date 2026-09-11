-- Second corrective addendum to the function-EXECUTE hardening work
-- (20260822000000, 20260822010000).
--
-- Direct post-deployment verification of 20260822010000 (a live
-- pg_proc.proacl/has_function_privilege query, not just a clean `db push`)
-- found that all 22 Category 2 (pure trigger) functions still show
-- authenticated_execute = true, e.g.
-- set_updated_at: {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
-- This is not a regression caused by either hardening migration — a grep
-- of every migration file's source found no `grant ... to authenticated`
-- for any of these 22 function names anywhere in this project's history,
-- and the pre-hardening enumeration (captured before 20260822000000 was
-- ever applied) already showed authenticated_execute = true uniformly
-- across all 49 functions, trigger functions included. authenticated has
-- held an individual EXECUTE grant on every function in `public` since
-- each was created — separate from, and in addition to, the PUBLIC
-- pseudo-role grant that 20260822010000 revoked. Revoking from PUBLIC
-- never touches an individual grant to a named role; that is the same
-- mechanism, applied to a different grantee, as the bug 20260822010000
-- itself corrected for anon.
--
-- Neither prior migration in this series ever issued an explicit REVOKE
-- of authenticated's access to these 22 functions specifically — the
-- original investigation's intent (see 20260822000000's header) was
-- always that Category 2 functions need EXECUTE from neither anon nor
-- authenticated, since Postgres gates trigger firing on table-level
-- INSERT/UPDATE/DELETE privilege, not caller EXECUTE on the trigger
-- function. This migration closes that gap.
revoke execute on function public.assessment_results_validate_tenant() from authenticated;
revoke execute on function public.assessments_validate_tenant() from authenticated;
revoke execute on function public.attendance_records_validate_tenant() from authenticated;
revoke execute on function public.class_teacher_assignments_validate_tenant() from authenticated;
revoke execute on function public.classes_validate_grade_school() from authenticated;
revoke execute on function public.employees_validate_department_school() from authenticated;
revoke execute on function public.employees_validate_profile_tenant() from authenticated;
revoke execute on function public.employees_validate_reports_to() from authenticated;
revoke execute on function public.learner_documents_validate_tenant() from authenticated;
revoke execute on function public.learner_emergency_contacts_validate_tenant() from authenticated;
revoke execute on function public.learner_enrollments_validate_tenant_and_grade() from authenticated;
revoke execute on function public.learner_guardians_validate_tenant() from authenticated;
revoke execute on function public.learner_medical_information_validate_tenant() from authenticated;
revoke execute on function public.learners_validate_status_transition() from authenticated;
revoke execute on function public.prevent_direct_email_change() from authenticated;
revoke execute on function public.prevent_direct_role_change() from authenticated;
revoke execute on function public.prevent_direct_tenant_change() from authenticated;
revoke execute on function public.prevent_direct_year_activation() from authenticated;
revoke execute on function public.prevent_self_status_change() from authenticated;
revoke execute on function public.set_created_updated_by() from authenticated;
revoke execute on function public.set_updated_at() from authenticated;
revoke execute on function public.terms_validate_academic_year_school() from authenticated;

-- service_role is untouched (retains EXECUTE on all 49 functions, as
-- established by 20260822010000 and not revisited here).
