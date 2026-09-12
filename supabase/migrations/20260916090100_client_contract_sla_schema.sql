-- Sebetsa Phase P — Client, Contract & SLA Management, migration 2 of 3.
--
-- Extends the existing Organisation > Region > Client > Site > Contract
-- backbone (Phase C) rather than duplicating it: client_contacts adds
-- multi-contact support the single primary_contact_* columns on `clients`
-- never covered; contract_documents reuses the Phase M private-bucket
-- pattern instead of a second insecure upload mechanism; sla_definitions/
-- sla_measurements are new, since nothing SLA-shaped existed before.
--
-- Write access continues to use can_manage_org_structure() (Phase C:
-- organization_administrator/operations_manager) for the org-hierarchy
-- extension (contacts, contract documents), matching the write tier
-- already governing clients/sites/contracts themselves.

-- ---------------------------------------------------------------------------
-- Contract lifecycle — now safe to reference 'expiring'/'suspended' (added
-- in the previous, already-committed migration).

create or replace function public.contracts_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status in ('active', 'terminated')) -- terminated: cancelled before activation
    or (old.status = 'active' and new.status in ('expiring', 'suspended', 'terminated'))
    or (old.status = 'expiring' and new.status in ('active', 'expired', 'terminated'))
    or (old.status = 'suspended' and new.status in ('active', 'terminated'))
  ) then
    raise exception 'invalid_transition: cannot move contract from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger contracts_validate_transition_trigger
  before update on public.contracts
  for each row
  execute function public.contracts_validate_transition();

-- ---------------------------------------------------------------------------
-- Client contacts — multiple named contacts per client, beyond the single
-- primary_contact_* columns already on `clients`.

create table public.client_contacts (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  client_id     uuid not null references public.clients (id) on delete cascade,
  name          text not null check (char_length(name) > 0),
  role_title    text,
  email         text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone         text,
  is_primary    boolean not null default false,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index client_contacts_tenant_id_idx on public.client_contacts (tenant_id);
create index client_contacts_client_id_idx on public.client_contacts (client_id);

create trigger client_contacts_set_updated_at
  before update on public.client_contacts
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_client_contact_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.clients c where c.id = new.client_id and c.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger client_contacts_validate_tenant_ref
  before insert or update on public.client_contacts
  for each row
  execute function public.validate_client_contact_tenant_ref();

alter table public.client_contacts enable row level security;
alter table public.client_contacts force row level security;

create policy client_contacts_select on public.client_contacts for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy client_contacts_write on public.client_contacts for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger client_contacts_audit_log
  after insert or update on public.client_contacts
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Contract documents — same private-bucket pattern as employee_documents
-- (Phase M): the metadata table is the real authorization boundary,
-- storage.objects policies re-check the same tenant/contract path segments.

create table public.contract_documents (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.organizations (id) on delete cascade,
  contract_id     uuid not null references public.contracts (id) on delete cascade,
  file_name       text not null check (char_length(file_name) > 0),
  mime_type       text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  file_size_bytes integer not null check (file_size_bytes > 0 and file_size_bytes <= 10485760),
  storage_path    text not null unique,
  version         integer not null default 1 check (version > 0),
  uploaded_by     uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now()
);

create index contract_documents_tenant_id_idx on public.contract_documents (tenant_id);
create index contract_documents_contract_id_idx on public.contract_documents (contract_id);

create or replace function public.validate_contract_document_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.contracts c where c.id = new.contract_id and c.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger contract_documents_validate_tenant_ref
  before insert on public.contract_documents
  for each row
  execute function public.validate_contract_document_tenant_ref();

alter table public.contract_documents enable row level security;
alter table public.contract_documents force row level security;

create policy contract_documents_select on public.contract_documents for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy contract_documents_insert on public.contract_documents for insert to authenticated
  with check (public.can_manage_org_structure(tenant_id));

-- No UPDATE/DELETE policy — a replacement is a new row (version + 1),
-- matching Phase M's non-destructive versioning; history is never erased.

create trigger contract_documents_audit_log
  after insert on public.contract_documents
  for each row
  execute function public.audit_log_from_trigger();

insert into storage.buckets (id, name, public)
values ('contract-documents', 'contract-documents', false)
on conflict (id) do nothing;

create policy contract_documents_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'contract-documents'
    and public.can_manage_org_structure((storage.foldername(name))[1]::uuid)
  );

create policy contract_documents_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'contract-documents'
    and public.can_manage_org_structure((storage.foldername(name))[1]::uuid)
  );

-- ---------------------------------------------------------------------------
-- SLA framework: tenant-defined metric targets against a contract/site,
-- and the periodic measurements computed from Sebetsa's own real
-- operational data (attendance, tasks, incidents, compliance) — never a
-- fabricated number.

create type public.sla_metric_type as enum (
  'staffing_fulfillment', 'task_completion_rate', 'incident_response_hours', 'compliance_completion_rate'
);

create table public.sla_definitions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  contract_id         uuid not null references public.contracts (id) on delete cascade,
  site_id             uuid references public.sites (id) on delete cascade,
  name                text not null check (char_length(name) > 0),
  metric_type         public.sla_metric_type not null,
  target_value        numeric(8, 2) not null,
  -- 'gte': measured value must be >= target (e.g. staffing/completion
  -- rates); 'lte': measured value must be <= target (e.g. response hours).
  threshold_operator  text not null check (threshold_operator in ('gte', 'lte')),
  measurement_period  text not null default 'monthly' check (measurement_period in ('weekly', 'monthly')),
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.sla_definitions is
  'target_value/threshold_operator define what "met" means for this metric — never inferred client-side.';

create index sla_definitions_tenant_id_idx on public.sla_definitions (tenant_id);
create index sla_definitions_contract_id_idx on public.sla_definitions (contract_id);

create trigger sla_definitions_set_updated_at
  before update on public.sla_definitions
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_sla_definition_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.contracts c where c.id = new.contract_id and c.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites s where s.id = new.site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger sla_definitions_validate_tenant_refs
  before insert or update on public.sla_definitions
  for each row
  execute function public.validate_sla_definition_tenant_refs();

alter table public.sla_definitions enable row level security;
alter table public.sla_definitions force row level security;

create policy sla_definitions_select on public.sla_definitions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy sla_definitions_write on public.sla_definitions for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger sla_definitions_audit_log
  after insert or update on public.sla_definitions
  for each row
  execute function public.audit_log_from_trigger();

create table public.sla_measurements (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  sla_definition_id uuid not null references public.sla_definitions (id) on delete cascade,
  period_start      date not null,
  period_end        date not null,
  measured_value    numeric(10, 2) not null,
  target_met        boolean not null,
  computed_by       uuid references public.profiles (id) on delete set null,
  computed_at       timestamptz not null default now(),
  check (period_end >= period_start)
);

comment on table public.sla_measurements is
  'Append-only — written only by compute_sla_measurement(), never a direct client write. measured_value/target_met are always derived from real Sebetsa operational tables at computation time, never client-supplied.';

create index sla_measurements_definition_idx on public.sla_measurements (sla_definition_id);
create index sla_measurements_tenant_id_idx on public.sla_measurements (tenant_id);

alter table public.sla_measurements enable row level security;
alter table public.sla_measurements force row level security;

create policy sla_measurements_select on public.sla_measurements for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

-- No direct client write — compute_sla_measurement() RPC only.
