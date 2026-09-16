-- Sebetsa — P1 remediation, discovered during this sprint's own §12 "look
-- for USING(true)-equivalent policies" broader RLS audit (not one of the
-- two named remaining HIGH findings, but the same severity class as the
-- original audit's C-2 CRITICAL finding: a blanket
-- `tenant_id = current_tenant_id() or is_platform_admin()` SELECT policy
-- with no role/permission predicate, on a table whose data is gated by a
-- specific permission in rolePermissions.ts that `employee`/`hr_user`/
-- `client_user` do not hold).
--
-- Scope discipline: only tables backing real operational/business DATA
-- with a directly corresponding gated permission are narrowed here.
-- Deliberately NOT touched, with rationale (documented again in
-- docs/SEBETSA_REMEDIATION_REPORT.md's "Remaining Risks"):
--   - leave_types, task_templates, training_programs,
--     training_requirements, attendance_policies, leave_policies,
--     skills: catalogue/reference/configuration tables, not gated by any
--     permission in rolePermissions.ts (leave_types' own
--     leave_types_select_all_tenant_members policy is *already*, by
--     design, `tenant_id = current_tenant_id()` with no role check at
--     all — every tenant member is meant to see what leave types/skills/
--     training programs/task templates exist, the same way every tenant
--     member sees what document types or task priorities exist; this is
--     the established, precedented shape for this class of table, not an
--     oversight).
--   - task_comments: needs the same multi-branch join
--     tasks_select_own_or_broad itself uses (own-assignee, own-
--     supervisor, own-team-member, or can_manage_operations) to stay
--     exactly consistent with its parent task's own visibility — a
--     higher-risk, more involved change deferred to its own dedicated
--     pass rather than rushed here; flagged as an open risk.
--
-- Fixed here: assets/asset_assignments/asset_maintenance_records
-- (asset.view), inventory_items/inventory_movements (inventory.view),
-- compliance_requirements (compliance.view — compliance_records, the
-- sibling tracked-instance table, already had the correct narrower
-- policy; the requirements/catalogue table was the outlier, not the
-- intended exception), client_contacts (org_structure.view — a client's
-- own child table that never received the same narrowing its parent
-- clients/sites/contracts/contract_sites tables did),
-- contract_documents/sla_definitions/sla_measurements (org_structure.view
-- — child data of contracts, same visibility as their parent),
-- employee_availability/employee_availability_exceptions
-- (availability.view — mirrors shifts_select_own_or_broad's own
-- can_view_scheduling_broad-or-own-employee shape exactly).
--
-- can_manage_operations() already carries exactly the asset.view/
-- inventory.view/compliance.view role set (organization_administrator,
-- operations_manager, regional_manager, site_manager, supervisor, plus
-- is_platform_admin()) — confirmed against rolePermissions.ts before
-- reuse, not assumed. No new helper function needed for those five
-- tables; can_view_org_structure_broad/can_view_scheduling_broad already
-- exist for the rest.

drop policy if exists assets_select on public.assets;
create policy assets_select on public.assets for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists asset_assignments_select on public.asset_assignments;
create policy asset_assignments_select on public.asset_assignments for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists asset_maintenance_records_select on public.asset_maintenance_records;
create policy asset_maintenance_records_select on public.asset_maintenance_records for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists inventory_items_select on public.inventory_items;
create policy inventory_items_select on public.inventory_items for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists inventory_movements_select on public.inventory_movements;
create policy inventory_movements_select on public.inventory_movements for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists compliance_requirements_select on public.compliance_requirements;
create policy compliance_requirements_select on public.compliance_requirements for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists client_contacts_select on public.client_contacts;
create policy client_contacts_select on public.client_contacts for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists contract_documents_select on public.contract_documents;
create policy contract_documents_select on public.contract_documents for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists sla_definitions_select on public.sla_definitions;
create policy sla_definitions_select on public.sla_definitions for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists sla_measurements_select on public.sla_measurements;
create policy sla_measurements_select on public.sla_measurements for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists employee_availability_select_within_tenant on public.employee_availability;
create policy employee_availability_select_broad on public.employee_availability for select to authenticated
  using (
    public.can_view_scheduling_broad(tenant_id)
    or exists (select 1 from public.employees e where e.id = employee_availability.employee_id and e.profile_id = auth.uid())
  );

drop policy if exists employee_availability_exceptions_select_within_tenant on public.employee_availability_exceptions;
create policy employee_availability_exceptions_select_broad on public.employee_availability_exceptions for select to authenticated
  using (
    public.can_view_scheduling_broad(tenant_id)
    or exists (select 1 from public.employees e where e.id = employee_availability_exceptions.employee_id and e.profile_id = auth.uid())
  );
