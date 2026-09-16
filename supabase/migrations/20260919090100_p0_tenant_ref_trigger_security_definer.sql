-- Sebetsa — P0 security remediation follow-up.
--
-- Every validate_*_tenant_refs() trigger function is plpgsql with no
-- explicit SECURITY clause, i.e. SECURITY INVOKER (Postgres's default):
-- its internal lookups against the referenced table (sites, employees,
-- clients, etc.) run under the CALLING role's own RLS. Before
-- 20260919090000_p0_tenant_rbac_remediation.sql narrowed several
-- blanket-SELECT policies, this was invisible — every authenticated
-- tenant member could read every row anyway, so the trigger's internal
-- lookup always succeeded. After that fix, a legitimately-authorized
-- WRITER role that is not also in the narrower VIEW role set for the
-- referenced table (e.g. a supervisor creating a shift references
-- sites.tenant_id, but supervisor no longer holds org_structure.view
-- on sites) gets a false cross_tenant_reference rejection, because the
-- trigger's own lookup now finds zero rows under RLS — not because the
-- reference is actually cross-tenant.
--
-- An FK-tenant integrity check is a system invariant, not a user-facing
-- data read — it only ever raises an exception or passes silently, and
-- never returns row data to the caller. It belongs behind the same
-- SECURITY DEFINER + locked search_path pattern already used by
-- current_tenant_id()/is_platform_admin() for exactly this reason: the
-- check itself must not depend on the caller's own read visibility.
-- Reproduced live: supabase/rls-tests/scheduling.sql's supervisor-
-- creates-a-shift assertion started failing with a false
-- cross_tenant_reference error after the P0 SELECT-policy fix, until
-- this migration was applied (see docs/SEBETSA_REMEDIATION_REPORT.md).

alter function public.validate_asset_tenant_refs() security definer;
alter function public.validate_asset_tenant_refs() set search_path = public;
alter function public.validate_attendance_break_tenant_ref() security definer;
alter function public.validate_attendance_break_tenant_ref() set search_path = public;
alter function public.validate_attendance_correction_tenant_ref() security definer;
alter function public.validate_attendance_correction_tenant_ref() set search_path = public;
alter function public.validate_attendance_record_tenant_refs() security definer;
alter function public.validate_attendance_record_tenant_refs() set search_path = public;
alter function public.validate_client_contact_tenant_ref() security definer;
alter function public.validate_client_contact_tenant_ref() set search_path = public;
alter function public.validate_compliance_record_tenant_refs() security definer;
alter function public.validate_compliance_record_tenant_refs() set search_path = public;
alter function public.validate_contract_document_tenant_ref() security definer;
alter function public.validate_contract_document_tenant_ref() set search_path = public;
alter function public.validate_development_action_tenant_ref() security definer;
alter function public.validate_development_action_tenant_ref() set search_path = public;
alter function public.validate_employee_availability_tenant_refs() security definer;
alter function public.validate_employee_availability_tenant_refs() set search_path = public;
alter function public.validate_employee_document_tenant_ref() security definer;
alter function public.validate_employee_document_tenant_ref() set search_path = public;
alter function public.validate_employee_qualification_tenant_refs() security definer;
alter function public.validate_employee_qualification_tenant_refs() set search_path = public;
alter function public.validate_employee_skill_tenant_refs() security definer;
alter function public.validate_employee_skill_tenant_refs() set search_path = public;
alter function public.validate_employee_tenant_refs() security definer;
alter function public.validate_employee_tenant_refs() set search_path = public;
alter function public.validate_incident_action_tenant_ref() security definer;
alter function public.validate_incident_action_tenant_ref() set search_path = public;
alter function public.validate_incident_affected_employee_tenant_ref() security definer;
alter function public.validate_incident_affected_employee_tenant_ref() set search_path = public;
alter function public.validate_incident_tenant_refs() security definer;
alter function public.validate_incident_tenant_refs() set search_path = public;
alter function public.validate_inventory_movement_tenant_refs() security definer;
alter function public.validate_inventory_movement_tenant_refs() set search_path = public;
alter function public.validate_leave_balance_tenant_refs() security definer;
alter function public.validate_leave_balance_tenant_refs() set search_path = public;
alter function public.validate_leave_balance_transaction_tenant_refs() security definer;
alter function public.validate_leave_balance_transaction_tenant_refs() set search_path = public;
alter function public.validate_leave_policy_tenant_refs() security definer;
alter function public.validate_leave_policy_tenant_refs() set search_path = public;
alter function public.validate_leave_request_leave_type_tenant_ref() security definer;
alter function public.validate_leave_request_leave_type_tenant_ref() set search_path = public;
alter function public.validate_leave_request_tenant_refs() security definer;
alter function public.validate_leave_request_tenant_refs() set search_path = public;
alter function public.validate_performance_review_tenant_ref() security definer;
alter function public.validate_performance_review_tenant_ref() set search_path = public;
alter function public.validate_position_tenant_refs() security definer;
alter function public.validate_position_tenant_refs() set search_path = public;
alter function public.validate_procurement_request_tenant_ref() security definer;
alter function public.validate_procurement_request_tenant_ref() set search_path = public;
alter function public.validate_shift_substitution_tenant_refs() security definer;
alter function public.validate_shift_substitution_tenant_refs() set search_path = public;
alter function public.validate_shift_tenant_refs() security definer;
alter function public.validate_shift_tenant_refs() set search_path = public;
alter function public.validate_site_assignment_tenant_refs() security definer;
alter function public.validate_site_assignment_tenant_refs() set search_path = public;
alter function public.validate_site_staffing_requirement_tenant_ref() security definer;
alter function public.validate_site_staffing_requirement_tenant_ref() set search_path = public;
alter function public.validate_sla_definition_tenant_refs() security definer;
alter function public.validate_sla_definition_tenant_refs() set search_path = public;
alter function public.validate_task_checklist_item_tenant_ref() security definer;
alter function public.validate_task_checklist_item_tenant_ref() set search_path = public;
alter function public.validate_task_comment_tenant_ref() security definer;
alter function public.validate_task_comment_tenant_ref() set search_path = public;
alter function public.validate_task_evidence_tenant_ref() security definer;
alter function public.validate_task_evidence_tenant_ref() set search_path = public;
alter function public.validate_task_template_tenant_refs() security definer;
alter function public.validate_task_template_tenant_refs() set search_path = public;
alter function public.validate_task_tenant_refs() security definer;
alter function public.validate_task_tenant_refs() set search_path = public;
alter function public.validate_team_member_tenant_refs() security definer;
alter function public.validate_team_member_tenant_refs() set search_path = public;
alter function public.validate_team_tenant_refs() security definer;
alter function public.validate_team_tenant_refs() set search_path = public;
alter function public.validate_training_enrollment_tenant_refs() security definer;
alter function public.validate_training_enrollment_tenant_refs() set search_path = public;
alter function public.validate_training_requirement_tenant_refs() security definer;
alter function public.validate_training_requirement_tenant_refs() set search_path = public;
