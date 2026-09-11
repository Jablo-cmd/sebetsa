-- Sebetsa Phase F — Workforce Management
-- Departments -> Positions -> Employees -> Teams -> Site Assignments.
--
-- Three additions on top of the Phase C schema (employees_and_teams.sql):
--
-- 1. Status columns on positions/teams (departments deliberately stays a
--    pure name catalogue, matching the Phase D decision already made for
--    it — nothing here revisits that).
--
-- 2. Cross-tenant relationship integrity. Every FK added in Phase C only
--    guarantees the referenced row EXISTS, not that it belongs to the same
--    tenant — e.g. nothing stopped `employees.department_id` from pointing
--    at another organization's department. The frontend was always going
--    to filter dropdowns to the caller's own tenant, but per this phase's
--    brief that is not sufficient on its own: the database must enforce it
--    too. Added as BEFORE INSERT OR UPDATE triggers (not just a CHECK
--    constraint — checking across tables requires a lookup, which a plain
--    CHECK can't express) on every table that gained a same-tenant FK in
--    Phase C.
--
-- 3. Broadened operational write access. Phase C put teams/team_members/
--    site_assignments behind can_manage_org_structure() (org admin /
--    operations manager only) — appropriate for the org hierarchy itself,
--    too narrow for day-to-day workforce operations. A site_manager or
--    supervisor legitimately builds their own site's team and assigns
--    their own staff; can_manage_operations() (added in
--    20260911101000_scheduling_and_attendance.sql) already exists for
--    exactly this operational tier. Departments/positions stay on
--    can_manage_org_structure (org-wide taxonomy, not day-to-day), but
--    gain an hr_user carve-out matching the one employees already has —
--    HR owns the department/position catalogue in practice.

alter table public.positions add column status public.entity_status not null default 'active';
alter table public.teams add column status public.entity_status not null default 'active';

-- ---------------------------------------------------------------------------
-- Cross-tenant relationship integrity triggers.

create or replace function public.validate_employee_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if new.department_id is not null and not exists (
    select 1 from public.departments where id = new.department_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: department % does not belong to tenant %', new.department_id, new.tenant_id;
  end if;

  if new.position_id is not null and not exists (
    select 1 from public.positions where id = new.position_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: position % does not belong to tenant %', new.position_id, new.tenant_id;
  end if;

  if new.supervisor_id is not null and not exists (
    select 1 from public.employees where id = new.supervisor_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: supervisor % does not belong to tenant %', new.supervisor_id, new.tenant_id;
  end if;

  if new.region_id is not null and not exists (
    select 1 from public.regions where id = new.region_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: region % does not belong to tenant %', new.region_id, new.tenant_id;
  end if;

  if new.home_site_id is not null and not exists (
    select 1 from public.sites where id = new.home_site_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.home_site_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger employees_validate_tenant_refs
  before insert or update on public.employees
  for each row
  execute function public.validate_employee_tenant_refs();

create or replace function public.validate_position_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if new.department_id is not null and not exists (
    select 1 from public.departments where id = new.department_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: department % does not belong to tenant %', new.department_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger positions_validate_tenant_refs
  before insert or update on public.positions
  for each row
  execute function public.validate_position_tenant_refs();

create or replace function public.validate_team_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if new.site_id is not null and not exists (
    select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  if new.lead_employee_id is not null and not exists (
    select 1 from public.employees where id = new.lead_employee_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.lead_employee_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger teams_validate_tenant_refs
  before insert or update on public.teams
  for each row
  execute function public.validate_team_tenant_refs();

create or replace function public.validate_team_member_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.teams where id = new.team_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: team % does not belong to tenant %', new.team_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger team_members_validate_tenant_refs
  before insert or update on public.team_members
  for each row
  execute function public.validate_team_member_tenant_refs();

create or replace function public.validate_site_assignment_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger site_assignments_validate_tenant_refs
  before insert or update on public.site_assignments
  for each row
  execute function public.validate_site_assignment_tenant_refs();

-- ---------------------------------------------------------------------------
-- Broadened write access: teams/team_members/site_assignments become
-- operational-tier (can_manage_operations), not org-structure-tier.

drop policy teams_write_by_manager on public.teams;
create policy teams_write_by_manager
  on public.teams for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

drop policy team_members_write_by_manager on public.team_members;
create policy team_members_write_by_manager
  on public.team_members for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

drop policy site_assignments_write_by_manager on public.site_assignments;
create policy site_assignments_write_by_manager
  on public.site_assignments for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

-- departments/positions gain the same hr_user carve-out employees already has.
drop policy departments_write_by_manager on public.departments;
create policy departments_write_by_manager
  on public.departments for all to authenticated
  using (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user')
  with check (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user');

drop policy positions_write_by_manager on public.positions;
create policy positions_write_by_manager
  on public.positions for all to authenticated
  using (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user')
  with check (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user');

-- ---------------------------------------------------------------------------
-- Audit trail: reuse audit_log_from_trigger() (added in
-- 20260911101500_org_hierarchy_audit_and_region_status.sql) for every
-- plain-table-write mutation in this domain. employees additionally has
-- explicit write_audit_log() calls inside terminate_employee/
-- reactivate_employee/admin_update_user_role — a status-changing action
-- through those RPCs produces both a specific event (e.g.
-- "employee_terminated") and this trigger's generic "update_employees"
-- row; that overlap is accepted as the cost of also covering plain
-- create/update writes, which had no audit coverage at all before this.

create trigger departments_audit_log
  after insert or update on public.departments
  for each row
  execute function public.audit_log_from_trigger();

create trigger positions_audit_log
  after insert or update on public.positions
  for each row
  execute function public.audit_log_from_trigger();

create trigger employees_audit_log
  after insert or update on public.employees
  for each row
  execute function public.audit_log_from_trigger();

create trigger teams_audit_log
  after insert or update on public.teams
  for each row
  execute function public.audit_log_from_trigger();

-- team_members has a composite primary key (team_id, employee_id) — no
-- `id` column — so the generic audit_log_from_trigger() (which reads
-- `.id`) doesn't fit. Dedicated variant using team_id as the audited
-- entity, matching "team membership changed" being a team-level event.
create or replace function public.audit_log_team_membership_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_team_id uuid;
  v_employee_id uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant_id := old.tenant_id;
    v_team_id := old.team_id;
    v_employee_id := old.employee_id;
  else
    v_tenant_id := new.tenant_id;
    v_team_id := new.team_id;
    v_employee_id := new.employee_id;
  end if;

  insert into public.audit_log (tenant_id, actor_profile_id, action, entity_table, entity_id, before, after)
  values (
    v_tenant_id, auth.uid(), lower(tg_op) || '_team_members', 'teams', v_team_id,
    case when tg_op = 'DELETE' then jsonb_build_object('employee_id', v_employee_id) else null end,
    case when tg_op != 'DELETE' then jsonb_build_object('employee_id', v_employee_id) else null end
  );

  return null;
end;
$$;

create trigger team_members_audit_log
  after insert or delete on public.team_members
  for each row
  execute function public.audit_log_team_membership_trigger();

create trigger site_assignments_audit_log
  after insert or update on public.site_assignments
  for each row
  execute function public.audit_log_from_trigger();
