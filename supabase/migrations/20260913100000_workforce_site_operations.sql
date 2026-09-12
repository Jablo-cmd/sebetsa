-- Sebetsa Phase J — Workforce & Site Operations.
--
-- Deliberately small: the domain model (regions/clients/sites/contracts/
-- employees/teams/site_assignments/shifts/attendance_records/tasks) already
-- exists — Phase J is an operational visibility layer over it, not a new
-- entity graph. The one genuinely new concept is configurable staffing
-- requirements (§J.3: "do not fabricate business rules... introduce
-- configurable structures rather than hard-coded numbers").
--
-- Site workforce/staffing aggregation itself is deliberately NOT a
-- database VIEW: a plain view is owned by the migration-applying role,
-- which is a Postgres superuser on a managed Supabase project — superusers
-- bypass RLS even on a FORCE ROW LEVEL SECURITY table, so a view here
-- would silently leak cross-tenant/cross-site data regardless of the
-- underlying tables' own policies. The frontend instead issues a handful
-- of direct, already-RLS-scoped count queries against site_assignments/
-- shifts/attendance_records/tasks — safe by construction, and not the kind
-- of N+1 pattern (per-row queries) the architecture principle warns about.

create table public.site_staffing_requirements (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.organizations (id) on delete cascade,
  site_id         uuid not null references public.sites (id) on delete cascade,
  label           text not null check (char_length(label) > 0),
  required_count  integer not null check (required_count >= 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (tenant_id, site_id, label)
);

comment on table public.site_staffing_requirements is
  'Configurable "this site needs N staff of this kind" rows — e.g. (Site A, "Day shift guards", 4). Not a scheduling entity itself; Site Operations compares this against actual scheduled/present counts to surface shortages. No hard-coded staffing numbers anywhere in the app.';

create index site_staffing_requirements_tenant_id_idx on public.site_staffing_requirements (tenant_id);
create index site_staffing_requirements_site_id_idx on public.site_staffing_requirements (site_id);

create trigger site_staffing_requirements_set_updated_at
  before update on public.site_staffing_requirements
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_site_staffing_requirement_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger site_staffing_requirements_validate_tenant_ref
  before insert or update on public.site_staffing_requirements
  for each row
  execute function public.validate_site_staffing_requirement_tenant_ref();

alter table public.site_staffing_requirements enable row level security;
alter table public.site_staffing_requirements force row level security;

create policy site_staffing_requirements_select_within_tenant on public.site_staffing_requirements for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy site_staffing_requirements_write_by_manager on public.site_staffing_requirements for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create trigger site_staffing_requirements_audit_log
  after insert or update on public.site_staffing_requirements
  for each row
  execute function public.audit_log_from_trigger();
