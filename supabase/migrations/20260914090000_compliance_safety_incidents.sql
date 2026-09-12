-- Sebetsa Phase N — Compliance, Safety & Incident Management, migration 1 of 2.
--
-- Two coordinated sub-domains:
--   1. Compliance: a tenant-configurable requirement catalogue
--      (compliance_requirements) instantiated per site/client/contract as
--      trackable compliance_records — regulations are never hard-coded,
--      only the requirement *shape* is fixed.
--   2. Incidents: a lifecycle-enforced incident register with corrective/
--      preventive actions, following the same "no direct client write,
--      RPC-only mutation, server-derived actor/timestamp" shape as
--      leave_requests (Phase H) and employee_documents (Phase M).
--
-- Write access to both sub-domains reuses can_manage_operations() (Phase G):
-- organization_administrator/operations_manager/regional_manager/
-- site_manager/supervisor — the same operational management tier already
-- governing scheduling/attendance/leave, so N does not introduce a
-- redundant permission tier. Employee-identifying links (who was affected,
-- who a requirement's evidence concerns) additionally respect
-- can_manage_employees() where the record could reveal HR-sensitive
-- information, mirroring Phase M's sensitivity split.

create type public.compliance_status as enum (
  'pending', 'in_progress', 'compliant', 'non_compliant', 'expired', 'waived'
);

create type public.incident_category as enum (
  'workplace_safety', 'property_damage', 'client_incident', 'near_miss', 'security', 'operational_other'
);

create type public.incident_severity as enum ('low', 'medium', 'high', 'critical');

create type public.incident_status as enum (
  'reported', 'acknowledged', 'investigating', 'corrective_action', 'pending_closure', 'closed'
);

create type public.incident_action_status as enum ('open', 'in_progress', 'completed', 'verified');

-- ---------------------------------------------------------------------------
-- Compliance requirement catalogue: tenant-defined, never hard-coded.

create table public.compliance_requirements (
  id                        uuid primary key default gen_random_uuid(),
  tenant_id                 uuid not null references public.organizations (id) on delete cascade,
  name                      text not null check (char_length(name) > 0),
  category                  text not null check (char_length(category) > 0),
  description               text,
  applies_to_scope          text not null check (applies_to_scope in ('organization', 'client', 'site', 'contract')),
  recurrence_interval_days  integer check (recurrence_interval_days > 0),
  is_active                 boolean not null default true,
  created_by                uuid references public.profiles (id) on delete set null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  unique (tenant_id, name)
);

comment on table public.compliance_requirements is
  'Tenant-configurable compliance catalogue — category/applies_to_scope are free-form/enumerated shape only, never a hard-coded list of actual regulations.';

create index compliance_requirements_tenant_id_idx on public.compliance_requirements (tenant_id);

create trigger compliance_requirements_set_updated_at
  before update on public.compliance_requirements
  for each row
  execute function public.set_updated_at();

alter table public.compliance_requirements enable row level security;
alter table public.compliance_requirements force row level security;

create policy compliance_requirements_select on public.compliance_requirements for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy compliance_requirements_write on public.compliance_requirements for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger compliance_requirements_audit_log
  after insert or update on public.compliance_requirements
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Compliance records: one instance of a requirement against a site/client/
-- contract, tracked to completion/expiry.

create table public.compliance_records (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null references public.organizations (id) on delete cascade,
  requirement_id           uuid not null references public.compliance_requirements (id) on delete cascade,
  site_id                  uuid references public.sites (id) on delete cascade,
  client_id                uuid references public.clients (id) on delete cascade,
  contract_id              uuid references public.contracts (id) on delete cascade,
  responsible_profile_id   uuid references public.profiles (id) on delete set null,
  status                   public.compliance_status not null default 'pending',
  due_date                 date,
  completed_date           date,
  expiry_date              date,
  evidence_storage_path    text,
  verified_by              uuid references public.profiles (id) on delete set null,
  verified_at              timestamptz,
  notes                    text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  check (
    (case when site_id is not null then 1 else 0 end)
    + (case when client_id is not null then 1 else 0 end)
    + (case when contract_id is not null then 1 else 0 end) <= 1
  )
);

comment on table public.compliance_records is
  'One tracked instance of a requirement. verified_by/verified_at are server-derived (verify_compliance_record RPC only) — never client-supplied.';

create index compliance_records_tenant_id_idx on public.compliance_records (tenant_id);
create index compliance_records_requirement_id_idx on public.compliance_records (requirement_id);
create index compliance_records_status_idx on public.compliance_records (status);
create index compliance_records_due_date_idx on public.compliance_records (due_date);
create index compliance_records_responsible_idx on public.compliance_records (responsible_profile_id);

create trigger compliance_records_set_updated_at
  before update on public.compliance_records
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_compliance_record_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.compliance_requirements r where r.id = new.requirement_id and r.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: requirement % does not belong to tenant %', new.requirement_id, new.tenant_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites s where s.id = new.site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.client_id is not null and not exists (select 1 from public.clients c where c.id = new.client_id and c.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts co where co.id = new.contract_id and co.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger compliance_records_validate_tenant_refs
  before insert or update on public.compliance_records
  for each row
  execute function public.validate_compliance_record_tenant_refs();

alter table public.compliance_records enable row level security;
alter table public.compliance_records force row level security;

create policy compliance_records_select on public.compliance_records for select to authenticated
  using (
    responsible_profile_id = auth.uid()
    or public.can_manage_operations(tenant_id)
  );

-- No direct client INSERT/UPDATE — upsert_compliance_record()/
-- verify_compliance_record() RPCs are the only write path.

create trigger compliance_records_audit_log
  after insert or update on public.compliance_records
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Incidents.

create sequence public.incidents_reference_seq;

create table public.incidents (
  id                       uuid primary key default gen_random_uuid(),
  tenant_id                uuid not null references public.organizations (id) on delete cascade,
  reference_number         text not null unique,
  site_id                  uuid references public.sites (id) on delete set null,
  contract_id              uuid references public.contracts (id) on delete set null,
  category                 public.incident_category not null,
  severity                 public.incident_severity not null,
  status                   public.incident_status not null default 'reported',
  occurred_at              timestamptz not null,
  reported_by              uuid references public.profiles (id) on delete set null,
  description              text not null check (char_length(description) > 0),
  investigation_notes      text,
  corrective_action_summary text,
  closed_by                uuid references public.profiles (id) on delete set null,
  closed_at                timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

comment on table public.incidents is
  'reference_number/status/reported_by/closed_by/closed_at are server-derived (report_incident/transition_incident_status RPCs only) — never client-supplied. No direct client write policy.';

create index incidents_tenant_id_idx on public.incidents (tenant_id);
create index incidents_site_id_idx on public.incidents (site_id);
create index incidents_status_idx on public.incidents (status);
create index incidents_severity_idx on public.incidents (severity);
create index incidents_occurred_at_idx on public.incidents (occurred_at);

create trigger incidents_set_updated_at
  before update on public.incidents
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_incident_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if new.site_id is not null and not exists (select 1 from public.sites s where s.id = new.site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts c where c.id = new.contract_id and c.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger incidents_validate_tenant_refs
  before insert or update on public.incidents
  for each row
  execute function public.validate_incident_tenant_refs();

-- Authoritative lifecycle — every other transition (including arbitrary
-- jumps) is rejected here, not just in the RPC layer, so even a future
-- direct-write bug can never bypass it.
create or replace function public.incidents_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'reported' and new.status = 'acknowledged')
    or (old.status = 'acknowledged' and new.status = 'investigating')
    or (old.status = 'investigating' and new.status = 'corrective_action')
    or (old.status = 'corrective_action' and new.status = 'pending_closure')
    or (old.status = 'pending_closure' and new.status = 'closed')
    or (old.status in ('pending_closure', 'closed') and new.status = 'investigating') -- justified reopen
  ) then
    raise exception 'invalid_transition: cannot move incident from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger incidents_validate_transition_trigger
  before update on public.incidents
  for each row
  execute function public.incidents_validate_transition();

-- ---------------------------------------------------------------------------
-- Affected employees (join table) — kept separate from incidents so a
-- multi-employee incident never forces sensitive per-employee visibility
-- onto the whole incident row. Created before incidents' own RLS policies
-- below, since incidents_select references this table.

create table public.incident_affected_employees (
  id            uuid primary key default gen_random_uuid(),
  -- Denormalized from incidents.tenant_id (kept in sync by a trigger) so
  -- this table's own RLS policy never has to query `incidents` — querying
  -- incidents from here while incidents' own policy queries this table
  -- back would be infinite RLS recursion.
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  incident_id   uuid not null references public.incidents (id) on delete cascade,
  employee_id   uuid not null references public.employees (id) on delete cascade,
  involvement   text not null default 'involved' check (involvement in ('injured', 'witness', 'involved')),
  created_at    timestamptz not null default now(),
  unique (incident_id, employee_id)
);

create index incident_affected_employees_incident_idx on public.incident_affected_employees (incident_id);
create index incident_affected_employees_employee_idx on public.incident_affected_employees (employee_id);

create or replace function public.validate_incident_affected_employee_tenant_ref()
returns trigger
language plpgsql
as $$
declare
  v_incident_tenant_id uuid;
  v_employee_tenant_id uuid;
begin
  select tenant_id into v_incident_tenant_id from public.incidents where id = new.incident_id;
  if v_incident_tenant_id is null then
    raise exception 'not_found: no incident %', new.incident_id;
  end if;
  if new.tenant_id <> v_incident_tenant_id then
    raise exception 'cross_tenant_reference: tenant_id does not match incident %''s tenant', new.incident_id;
  end if;

  select tenant_id into v_employee_tenant_id from public.employees where id = new.employee_id;
  if v_employee_tenant_id is distinct from v_incident_tenant_id then
    raise exception 'cross_tenant_reference: employee % does not belong to incident %''s tenant', new.employee_id, new.incident_id;
  end if;

  return new;
end;
$$;

create trigger incident_affected_employees_validate_tenant_ref
  before insert or update on public.incident_affected_employees
  for each row
  execute function public.validate_incident_affected_employee_tenant_ref();

alter table public.incident_affected_employees enable row level security;
alter table public.incident_affected_employees force row level security;

alter table public.incidents enable row level security;
alter table public.incidents force row level security;

create policy incidents_select on public.incidents for select to authenticated
  using (
    reported_by = auth.uid()
    or exists (
      select 1 from public.incident_affected_employees iae
      join public.employees e on e.id = iae.employee_id
      where iae.incident_id = incidents.id and e.profile_id = auth.uid()
    )
    -- `security_invoker = false` on this exists() would be ideal, but
    -- Postgres RLS has no per-subquery invoker toggle — instead,
    -- incident_affected_employees' own policy below is written to never
    -- query `incidents`, breaking the recursion this cross-reference would
    -- otherwise create.
    or public.can_manage_operations(tenant_id)
  );

-- No direct client INSERT/UPDATE — report_incident()/transition_incident_
-- status() RPCs are the only write path.

create trigger incidents_audit_log
  after insert or update on public.incidents
  for each row
  execute function public.audit_log_from_trigger();

create policy incident_affected_employees_select on public.incident_affected_employees for select to authenticated
  using (
    exists (select 1 from public.employees e where e.id = incident_affected_employees.employee_id and e.profile_id = auth.uid())
    or public.can_manage_operations(tenant_id)
    or public.can_manage_employees(tenant_id)
  );

-- No direct client write — written only by report_incident()/
-- link_incident_employee() RPCs.

-- ---------------------------------------------------------------------------
-- Corrective / preventive actions.

create table public.incident_actions (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  incident_id       uuid not null references public.incidents (id) on delete cascade,
  description       text not null check (char_length(description) > 0),
  owner_profile_id  uuid references public.profiles (id) on delete set null,
  due_date          date,
  status            public.incident_action_status not null default 'open',
  completed_at      timestamptz,
  verified_by       uuid references public.profiles (id) on delete set null,
  verified_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.incident_actions is
  'completed_at/verified_by/verified_at are server-derived (complete_incident_action/verify_incident_action RPCs only).';

create index incident_actions_tenant_id_idx on public.incident_actions (tenant_id);
create index incident_actions_incident_idx on public.incident_actions (incident_id);
create index incident_actions_owner_idx on public.incident_actions (owner_profile_id);
create index incident_actions_status_idx on public.incident_actions (status);
create index incident_actions_due_date_idx on public.incident_actions (due_date);

create trigger incident_actions_set_updated_at
  before update on public.incident_actions
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_incident_action_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.incidents i where i.id = new.incident_id and i.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: incident % does not belong to tenant %', new.incident_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger incident_actions_validate_tenant_ref
  before insert or update on public.incident_actions
  for each row
  execute function public.validate_incident_action_tenant_ref();

alter table public.incident_actions enable row level security;
alter table public.incident_actions force row level security;

create policy incident_actions_select on public.incident_actions for select to authenticated
  using (
    owner_profile_id = auth.uid()
    or public.can_manage_operations(tenant_id)
  );

-- No direct client write — add_incident_action()/complete_incident_action()/
-- verify_incident_action() RPCs are the only write path.

create trigger incident_actions_audit_log
  after insert or update on public.incident_actions
  for each row
  execute function public.audit_log_from_trigger();
