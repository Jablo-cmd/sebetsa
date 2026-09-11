-- Sebetsa Phase C — Organisation Hierarchy
-- Organisation > Region > Client > Site > Contract, per the operational
-- backbone. Every table carries tenant_id (references organizations) and
-- follows the same RLS shape as profiles/organizations: readable within the
-- tenant, writable by org-level management roles or a platform admin.

create type public.entity_status as enum ('active', 'inactive', 'onboarding', 'offboarded');
create type public.contract_status as enum ('draft', 'active', 'expired', 'terminated');

-- Shared write-access check for org-hierarchy tables: org admins and
-- operations managers manage structure within their own tenant.
create or replace function public.can_manage_org_structure(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('organization_administrator', 'operations_manager')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_org_structure(uuid) is
  'True for organization_administrator/operations_manager of the target tenant, or any platform admin. Governs writes to regions/clients/sites/contracts.';

grant execute on function public.can_manage_org_structure(uuid) to authenticated;

-- ---------------------------------------------------------------------------
create table public.regions (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  name        text not null check (char_length(name) > 0),
  code        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create index regions_tenant_id_idx on public.regions (tenant_id);

create trigger regions_set_updated_at
  before update on public.regions
  for each row
  execute function public.set_updated_at();

alter table public.regions enable row level security;
alter table public.regions force row level security;

create policy regions_select_within_tenant
  on public.regions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy regions_write_by_manager
  on public.regions for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

-- ---------------------------------------------------------------------------
create table public.clients (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  region_id             uuid references public.regions (id) on delete set null,
  name                  text not null check (char_length(name) > 0),
  industry              text,
  primary_contact_name  text,
  primary_contact_email text check (primary_contact_email is null or primary_contact_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  primary_contact_phone text,
  status                public.entity_status not null default 'active',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index clients_tenant_id_idx on public.clients (tenant_id);
create index clients_region_id_idx on public.clients (region_id);

create trigger clients_set_updated_at
  before update on public.clients
  for each row
  execute function public.set_updated_at();

alter table public.clients enable row level security;
alter table public.clients force row level security;

create policy clients_select_within_tenant
  on public.clients for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy clients_write_by_manager
  on public.clients for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

-- ---------------------------------------------------------------------------
create table public.sites (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  client_id   uuid not null references public.clients (id) on delete cascade,
  region_id   uuid references public.regions (id) on delete set null,
  name        text not null check (char_length(name) > 0),
  address     text,
  site_type   text,
  status      public.entity_status not null default 'onboarding',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index sites_tenant_id_idx on public.sites (tenant_id);
create index sites_client_id_idx on public.sites (client_id);
create index sites_region_id_idx on public.sites (region_id);

create trigger sites_set_updated_at
  before update on public.sites
  for each row
  execute function public.set_updated_at();

alter table public.sites enable row level security;
alter table public.sites force row level security;

create policy sites_select_within_tenant
  on public.sites for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy sites_write_by_manager
  on public.sites for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

-- ---------------------------------------------------------------------------
create table public.contracts (
  id                     uuid primary key default gen_random_uuid(),
  tenant_id              uuid not null references public.organizations (id) on delete cascade,
  client_id              uuid not null references public.clients (id) on delete cascade,
  contract_number        text not null,
  start_date             date not null,
  end_date               date,
  status                 public.contract_status not null default 'draft',
  responsible_manager_id uuid references public.profiles (id) on delete set null,
  sla_notes              text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (tenant_id, contract_number),
  check (end_date is null or end_date >= start_date)
);

create index contracts_tenant_id_idx on public.contracts (tenant_id);
create index contracts_client_id_idx on public.contracts (client_id);
create index contracts_status_idx on public.contracts (status);

create trigger contracts_set_updated_at
  before update on public.contracts
  for each row
  execute function public.set_updated_at();

alter table public.contracts enable row level security;
alter table public.contracts force row level security;

create policy contracts_select_within_tenant
  on public.contracts for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy contracts_write_by_manager
  on public.contracts for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

-- A contract can cover multiple sites, and a site can be covered by more
-- than one contract over time (renewals).
create table public.contract_sites (
  contract_id  uuid not null references public.contracts (id) on delete cascade,
  site_id      uuid not null references public.sites (id) on delete cascade,
  tenant_id    uuid not null references public.organizations (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (contract_id, site_id)
);

create index contract_sites_tenant_id_idx on public.contract_sites (tenant_id);
create index contract_sites_site_id_idx on public.contract_sites (site_id);

alter table public.contract_sites enable row level security;
alter table public.contract_sites force row level security;

create policy contract_sites_select_within_tenant
  on public.contract_sites for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy contract_sites_write_by_manager
  on public.contract_sites for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));
