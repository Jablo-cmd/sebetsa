-- Sebetsa Phase H — Leave & Absence, migration 2 of 6.
--
-- leave_types: tenant-configurable leave category catalogue (not a closed
-- enum — see the approved Phase H architecture §6: a tenant needs to add a
-- category without a schema migration).
--
-- leave_policies: the minimum viable per-tenant/per-type policy knobs
-- (§11/§13) — no rules engine, no approval-chain configuration, no
-- blackout periods.
--
-- Permission helpers mirror ROLE_PERMISSIONS in
-- src/features/rbac/constants/rolePermissions.ts exactly (this migration
-- does not change that mapping, only expresses it in SQL):
--   leave.manage  -> organization_administrator, operations_manager, hr_user
--   leave.approve -> the above PLUS regional_manager
--   leave.view (broad/tenant) -> the above PLUS site_manager
-- `employee` and a request's own supervisor-less self access is handled at
-- the leave_requests table separately (own-row clauses), not through these
-- tenant-wide helpers.

create or replace function public.can_manage_leave(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('organization_administrator', 'operations_manager', 'hr_user')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_leave(uuid) is
  'True for organization_administrator/operations_manager/hr_user of the target tenant, or a platform admin. Governs leave type/policy configuration and balance adjustments — mirrors leave.manage in rolePermissions.ts.';

grant execute on function public.can_manage_leave(uuid) to authenticated;

create or replace function public.can_approve_leave(target_tenant_id uuid)
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

comment on function public.can_approve_leave(uuid) is
  'True for can_manage_leave''s role set plus regional_manager, of the target tenant, or a platform admin. Governs leave approve/reject/revoke and creating a request on another employee''s behalf — mirrors leave.approve in rolePermissions.ts.';

grant execute on function public.can_approve_leave(uuid) to authenticated;

create or replace function public.can_view_leave_broad(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('organization_administrator', 'operations_manager', 'regional_manager', 'site_manager', 'hr_user')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_leave_broad(uuid) is
  'True for can_approve_leave''s role set plus site_manager (view-only, no approve), of the target tenant, or a platform admin. Governs tenant-wide leave visibility — mirrors leave.view in rolePermissions.ts. Does NOT grant approval; that is can_approve_leave. An ordinary employee''s own-row access is handled separately at each table, not through this helper — leave.view for `employee` means own-only, per the approved architecture.';

grant execute on function public.can_view_leave_broad(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- leave_types

create table public.leave_types (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.organizations (id) on delete cascade,
  name                    text not null check (char_length(name) > 0),
  is_paid                 boolean not null default true,
  requires_documentation  boolean not null default false,
  default_annual_days     numeric check (default_annual_days is null or default_annual_days >= 0),
  status                  public.entity_status not null default 'active',
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (tenant_id, name)
);

comment on table public.leave_types is
  'Tenant-configurable leave categories. Deactivate via status=inactive rather than deleting — leave_requests/leave_policies/leave_balances reference these and must never lose their category.';

create index leave_types_tenant_id_idx on public.leave_types (tenant_id);

create trigger leave_types_set_updated_at
  before update on public.leave_types
  for each row
  execute function public.set_updated_at();

alter table public.leave_types enable row level security;
alter table public.leave_types force row level security;

create policy leave_types_select_within_tenant on public.leave_types for select to authenticated
  using (public.can_view_leave_broad(tenant_id) or tenant_id = public.current_tenant_id());
create policy leave_types_write_by_manager on public.leave_types for all to authenticated
  using (public.can_manage_leave(tenant_id)) with check (public.can_manage_leave(tenant_id));

create trigger leave_types_audit_log
  after insert or update on public.leave_types
  for each row
  execute function public.audit_log_from_trigger();

-- Every tenant member (including a plain employee, who needs the catalogue
-- to submit a request) can read active leave types — narrower than
-- can_view_leave_broad's manager tier. Kept as a second, additive SELECT
-- policy (Postgres OR-combines multiple permissive policies on the same
-- command) rather than loosening leave_types_select_within_tenant itself.
create policy leave_types_select_all_tenant_members on public.leave_types for select to authenticated
  using (tenant_id = public.current_tenant_id());

-- ---------------------------------------------------------------------------
-- leave_policies

create table public.leave_policies (
  id                      uuid primary key default gen_random_uuid(),
  tenant_id               uuid not null references public.organizations (id) on delete cascade,
  leave_type_id           uuid not null references public.leave_types (id) on delete cascade,
  default_annual_days     numeric check (default_annual_days is null or default_annual_days >= 0),
  max_carry_over_days     numeric check (max_carry_over_days is null or max_carry_over_days >= 0),
  min_notice_days         integer not null default 0 check (min_notice_days >= 0),
  requires_documentation  boolean not null default false,
  max_consecutive_days    numeric check (max_consecutive_days is null or max_consecutive_days >= 0),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (tenant_id, leave_type_id)
);

comment on table public.leave_policies is
  'Minimum viable per-tenant/per-type policy knobs (notice period, documentation, carry-over cap, consecutive-day cap). Not a rules engine — no approval-chain or blackout-period configuration.';

create index leave_policies_tenant_id_idx on public.leave_policies (tenant_id);
create index leave_policies_leave_type_id_idx on public.leave_policies (leave_type_id);

create trigger leave_policies_set_updated_at
  before update on public.leave_policies
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_leave_policy_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.leave_types where id = new.leave_type_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: leave type % does not belong to tenant %', new.leave_type_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger leave_policies_validate_tenant_refs
  before insert or update on public.leave_policies
  for each row
  execute function public.validate_leave_policy_tenant_refs();

alter table public.leave_policies enable row level security;
alter table public.leave_policies force row level security;

create policy leave_policies_select_within_tenant on public.leave_policies for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy leave_policies_write_by_manager on public.leave_policies for all to authenticated
  using (public.can_manage_leave(tenant_id)) with check (public.can_manage_leave(tenant_id));

create trigger leave_policies_audit_log
  after insert or update on public.leave_policies
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Default leave-type seeding. A South African operational-workforce
-- starter set, not a claim of automatic statutory compliance (see
-- architecture §6/§101) — a tenant can rename, deactivate, or add to these
-- freely afterward.

create or replace function public.seed_default_leave_types(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.leave_types (tenant_id, name, is_paid, requires_documentation, default_annual_days)
  select p_tenant_id, v.name, v.is_paid, v.requires_documentation, v.default_annual_days
  from (values
    ('Annual', true, false, 15::numeric),
    ('Sick', true, true, 10::numeric),
    ('Family Responsibility', true, false, 3::numeric),
    ('Maternity', false, true, null::numeric),
    ('Parental', false, true, null::numeric),
    ('Adoption', false, true, null::numeric),
    ('Commissioning Parental', false, true, null::numeric),
    ('Unpaid', false, false, null::numeric),
    ('Study', false, true, null::numeric),
    ('Other', false, false, null::numeric)
  ) as v(name, is_paid, requires_documentation, default_annual_days)
  where not exists (
    select 1 from public.leave_types lt where lt.tenant_id = p_tenant_id and lt.name = v.name
  );
end;
$$;

comment on function public.seed_default_leave_types(uuid) is
  'Idempotent starter set of SA-oriented leave categories for one tenant. Not a legal-compliance claim (see leave_types_and_policies migration header) — a tenant may rename/deactivate/add freely. Called once below for every existing tenant. NOT granted to authenticated — it takes a raw tenant_id with no caller-permission check, so it must only ever be invoked from a trusted server-side context (this migration, or a future tenant-onboarding SECURITY DEFINER RPC that itself checks the caller''s privilege before calling this).';

revoke execute on function public.seed_default_leave_types(uuid) from public;

do $$
declare
  v_tenant record;
begin
  for v_tenant in select id from public.organizations loop
    perform public.seed_default_leave_types(v_tenant.id);
  end loop;
end $$;

-- Auto-seed for every future tenant too — otherwise a newly created
-- organization would have zero leave_types and submit_leave_request could
-- never succeed for it until someone remembered a manual step.
create or replace function public.organizations_seed_leave_types()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.seed_default_leave_types(new.id);
  return new;
end;
$$;

create trigger organizations_seed_leave_types_trigger
  after insert on public.organizations
  for each row
  execute function public.organizations_seed_leave_types();
