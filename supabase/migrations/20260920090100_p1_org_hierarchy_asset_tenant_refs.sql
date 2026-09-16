-- Sebetsa — P1 remediation (docs/SEBETSA_REMEDIATION_REPORT.md "Remaining
-- Risks" #2): clients/sites/contracts/contract_sites/asset_assignments
-- never received the cross-tenant FK-validation trigger every other
-- relationship table in this codebase has (see e.g. validate_employee_tenant_refs,
-- validate_shift_tenant_refs, validate_asset_tenant_refs — all
-- SECURITY DEFINER with a locked search_path, following
-- 20260919090100_p0_tenant_ref_trigger_security_definer.sql's fix for why
-- that matters: a SECURITY INVOKER trigger's own internal lookups would be
-- subject to the calling role's narrower RLS-scoped SELECT policy).
--
-- Scope, matching the established codebase convention exactly (see
-- validate_employee_tenant_refs, which checks department_id/position_id/
-- supervisor_id/region_id/home_site_id but not profile-linked actor
-- columns; employee_documents' uploaded_by/verified_by are likewise never
-- tenant-validated by any trigger): these triggers validate structural
-- relationship columns only (region_id, client_id, site_id, contract_id,
-- employee_id, team_id) — never profile_id "actor" columns
-- (contracts.responsible_manager_id, asset_assignments.assigned_by),
-- which are always server-derived from auth.uid() inside a SECURITY
-- DEFINER RPC that already gates on a permission check for the target
-- tenant, so the actor's own tenant is not itself an integrity concern the
-- same way a structural reference is.
--
-- No admin bypass is added — matching every one of the ~38 existing
-- validate_*_tenant_refs triggers, none of which exempt is_platform_admin().
-- A platform administrator legitimately reads/writes across tenants via
-- the RLS layer's own explicit is_platform_admin() OR-branch, but must
-- never be able to construct a row that itself links two different
-- tenants' data together — that would corrupt tenant boundaries for every
-- subsequent (non-admin) reader of that row, which is a data-integrity
-- concern independent of who is currently allowed to see it.

-- ---------------------------------------------------------------------------
-- clients.region_id must belong to the same tenant.

create or replace function public.validate_client_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.region_id is not null and not exists (
    select 1 from public.regions where id = new.region_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: region % does not belong to tenant %', new.region_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger clients_validate_tenant_refs
  before insert or update on public.clients
  for each row
  execute function public.validate_client_tenant_refs();

-- ---------------------------------------------------------------------------
-- sites.client_id and sites.region_id must belong to the same tenant.

create or replace function public.validate_site_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;

  if new.region_id is not null and not exists (
    select 1 from public.regions where id = new.region_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: region % does not belong to tenant %', new.region_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger sites_validate_tenant_refs
  before insert or update on public.sites
  for each row
  execute function public.validate_site_tenant_refs();

-- ---------------------------------------------------------------------------
-- contracts.client_id must belong to the same tenant.

create or replace function public.validate_contract_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger contracts_validate_tenant_refs
  before insert or update on public.contracts
  for each row
  execute function public.validate_contract_tenant_refs();

-- ---------------------------------------------------------------------------
-- contract_sites.contract_id and .site_id must both belong to the same
-- tenant as the join row itself (and therefore to each other).

create or replace function public.validate_contract_site_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;

  if not exists (
    select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger contract_sites_validate_tenant_refs
  before insert or update on public.contract_sites
  for each row
  execute function public.validate_contract_site_tenant_refs();

-- ---------------------------------------------------------------------------
-- asset_assignments: asset_id always required; exactly one of
-- assigned_to_employee_id/assigned_to_team_id/assigned_to_site_id is set
-- (existing CHECK constraint) — validate whichever is present.
--
-- The table has no direct client write policy at all (assign_asset() is
-- the only path — see its own migration's comment), but assign_asset()
-- itself performs no tenant check on the three assignment target IDs
-- before this trigger's fix, so this is the first real enforcement point
-- for that specific gap, not a redundant belt-and-suspenders layer.

create or replace function public.validate_asset_assignment_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.assets where id = new.asset_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: asset % does not belong to tenant %', new.asset_id, new.tenant_id;
  end if;

  if new.assigned_to_employee_id is not null and not exists (
    select 1 from public.employees where id = new.assigned_to_employee_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.assigned_to_employee_id, new.tenant_id;
  end if;

  if new.assigned_to_team_id is not null and not exists (
    select 1 from public.teams where id = new.assigned_to_team_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: team % does not belong to tenant %', new.assigned_to_team_id, new.tenant_id;
  end if;

  if new.assigned_to_site_id is not null and not exists (
    select 1 from public.sites where id = new.assigned_to_site_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.assigned_to_site_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger asset_assignments_validate_tenant_refs
  before insert or update on public.asset_assignments
  for each row
  execute function public.validate_asset_assignment_tenant_refs();
