-- Sebetsa — P0 security remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, Critical findings C-1 and C-2).
--
-- C-1: employees_write_by_manager's second OR-branch checked only
-- `role = 'hr_user'` with NO tenant comparison, so any hr_user in ANY
-- tenant could read/write/delete every tenant's employees table via
-- `UPDATE public.employees SET first_name = first_name RETURNING *;` (no
-- WHERE clause) or `DELETE FROM public.employees;`. Reproduced live
-- against a real Postgres instance running every migration in this repo
-- before this fix (see docs/SEBETSA_REMEDIATION_REPORT.md).
--
-- C-2: employees, departments, positions, teams, team_members,
-- site_assignments, regions, clients, sites, contracts, contract_sites,
-- shifts, shift_substitutions, shift_definitions, site_staffing_requirements
-- and profiles all had a bare `tenant_id = current_tenant_id() or
-- is_platform_admin()` SELECT policy with NO role check at all — any
-- authenticated tenant member, including the zero-permission `client_user`
-- role and the deliberately-minimal `employee` role (see the "deliberately
-- minimal" comment in src/features/rbac/constants/rolePermissions.ts),
-- could read data the frontend's own permission catalogue says they
-- should never see (the full employee PII directory, every client's
-- contracts, every user's profile, etc).
--
-- Every replacement policy below is derived directly from the actual,
-- already-shipped authorization intent in
-- src/features/rbac/constants/rolePermissions.ts — which role holds which
-- `.view` permission — not invented. Where a role set exactly matches an
-- existing can_manage_*() helper's role list, that helper is reused rather
-- than duplicated. Four new helpers are added for role sets that don't
-- already have one. `employees` and `shifts` additionally keep a
-- self-access carve-out because real self-service pages
-- (src/pages/MyProfilePage.tsx, src/features/scheduling/pages/
-- MySchedulePage.tsx) depend on it — same "broad tier OR own record"
-- shape already established for attendance_records
-- (20260913090100_attendance_rls_hardening.sql) and leave_requests
-- (20260912090200_leave_requests_lifecycle.sql).
--
-- One known, deliberate UX consequence, not a bug: `scheduling.view` is
-- granted to the plain `employee` role (so a plain employee may reach the
-- shared /schedule grid, not just /schedule/mine), but `employee.view` is
-- NOT granted to `employee` (rolePermissions.ts's own "deliberately
-- minimal" design). After this fix, a plain employee viewing the shared
-- schedule grid can see that a shift belongs to some other employee_id,
-- but can no longer resolve that colleague's name/PII via a join to
-- `employees`, because they were never supposed to hold employee.view.
-- This is the RLS boundary agreeing with the frontend's own already-stated
-- intent, not a new restriction invented here.

-- ---------------------------------------------------------------------
-- New role-set helpers, each named after the exact rolePermissions.ts
-- permission whose granted-role list it reproduces.
-- ---------------------------------------------------------------------

-- employee.view / department.view / position.view: verified identical
-- role sets in rolePermissions.ts (organization_administrator,
-- operations_manager, regional_manager, site_manager, supervisor,
-- hr_user) — one helper for all three.
create or replace function public.can_view_workforce_directory(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('organization_administrator', 'operations_manager', 'regional_manager', 'site_manager', 'supervisor', 'hr_user')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_workforce_directory(uuid) is
  'Role set granted employee.view/department.view/position.view in rolePermissions.ts. Deliberately excludes employee and client_user.';

-- org_structure.view: organization_administrator, operations_manager,
-- regional_manager, site_manager. Narrower than can_manage_org_structure()
-- (write access), which excludes regional_manager/site_manager.
create or replace function public.can_view_org_structure_broad(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('organization_administrator', 'operations_manager', 'regional_manager', 'site_manager')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_org_structure_broad(uuid) is
  'Role set granted org_structure.view in rolePermissions.ts (regions/clients/sites/contracts/contract_sites read access).';

-- profile.view_any: organization_administrator, operations_manager,
-- regional_manager, hr_user. Not the same set as can_manage_profiles()
-- (write access), which excludes regional_manager.
create or replace function public.can_view_profiles_broad(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('organization_administrator', 'operations_manager', 'regional_manager', 'hr_user')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_profiles_broad(uuid) is
  'Role set granted profile.view_any in rolePermissions.ts.';

-- scheduling.view: the can_manage_operations() tier PLUS the plain
-- `employee` role (rolePermissions.ts grants employee 'scheduling.view'
-- so self-service users can see the shared schedule grid, not just
-- /schedule/mine). hr_user and client_user are excluded either way.
create or replace function public.can_view_scheduling_broad(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    public.can_manage_operations(target_tenant_id)
    or (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'employee'
    )
$$;

comment on function public.can_view_scheduling_broad(uuid) is
  'Role set granted scheduling.view in rolePermissions.ts: can_manage_operations() tier plus the plain employee role.';

-- ---------------------------------------------------------------------
-- C-1: bind employees_write_by_manager's hr_user branch to tenant.
-- ---------------------------------------------------------------------

drop policy if exists employees_write_by_manager on public.employees;

create policy employees_write_by_manager on public.employees for all to authenticated
  using (
    public.can_manage_org_structure(tenant_id)
    or (
      tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user'
    )
  )
  with check (
    public.can_manage_org_structure(tenant_id)
    or (
      tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user'
    )
  );

-- ---------------------------------------------------------------------
-- C-2: narrow every blanket "any tenant member" SELECT policy.
-- ---------------------------------------------------------------------

drop policy if exists employees_select_within_tenant on public.employees;
create policy employees_select_own_or_broad on public.employees for select to authenticated
  using (
    public.can_view_workforce_directory(tenant_id)
    or profile_id = auth.uid()
  );

drop policy if exists departments_select_within_tenant on public.departments;
create policy departments_select_broad on public.departments for select to authenticated
  using (public.can_view_workforce_directory(tenant_id));

drop policy if exists positions_select_within_tenant on public.positions;
create policy positions_select_broad on public.positions for select to authenticated
  using (public.can_view_workforce_directory(tenant_id));

drop policy if exists teams_select_within_tenant on public.teams;
create policy teams_select_broad on public.teams for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists team_members_select_within_tenant on public.team_members;
create policy team_members_select_broad on public.team_members for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists site_assignments_select_within_tenant on public.site_assignments;
create policy site_assignments_select_broad on public.site_assignments for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists regions_select_within_tenant on public.regions;
create policy regions_select_broad on public.regions for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists clients_select_within_tenant on public.clients;
create policy clients_select_broad on public.clients for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists sites_select_within_tenant on public.sites;
create policy sites_select_broad on public.sites for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists contracts_select_within_tenant on public.contracts;
create policy contracts_select_broad on public.contracts for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists contract_sites_select_within_tenant on public.contract_sites;
create policy contract_sites_select_broad on public.contract_sites for select to authenticated
  using (public.can_view_org_structure_broad(tenant_id));

drop policy if exists shifts_select_within_tenant on public.shifts;
create policy shifts_select_own_or_broad on public.shifts for select to authenticated
  using (
    public.can_view_scheduling_broad(tenant_id)
    or exists (select 1 from public.employees e where e.id = shifts.employee_id and e.profile_id = auth.uid())
  );

drop policy if exists shift_substitutions_select_within_tenant on public.shift_substitutions;
create policy shift_substitutions_select_broad on public.shift_substitutions for select to authenticated
  using (public.can_view_scheduling_broad(tenant_id));

drop policy if exists shift_definitions_select_within_tenant on public.shift_definitions;
create policy shift_definitions_select_broad on public.shift_definitions for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists site_staffing_requirements_select_within_tenant on public.site_staffing_requirements;
create policy site_staffing_requirements_select_broad on public.site_staffing_requirements for select to authenticated
  using (public.can_manage_operations(tenant_id));

drop policy if exists profiles_select_own_or_tenant_or_platform_admin on public.profiles;
create policy profiles_select_own_or_broad on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or public.can_view_profiles_broad(tenant_id)
  );
