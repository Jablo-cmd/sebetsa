-- Sebetsa Phase Y — Proof of Service audit trail.
--
-- The report itself is generated client-side (jsPDF/jsPDF-AutoTable,
-- already installed dependencies, previously unused anywhere in this
-- codebase — confirmed by repo-wide search) from real persisted data
-- (attendance_records, tasks, inspections, variation_orders) fetched
-- through the existing RLS-governed read paths — never a second copy of
-- that data. This table is only the audit trail: who generated a report,
-- for which site/period, and when — the brief's own requirement that
-- "proof report generation" be an audited action.

create table public.service_report_generations (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  client_id     uuid not null references public.clients (id) on delete cascade,
  site_id       uuid not null references public.sites (id) on delete cascade,
  contract_id   uuid references public.contracts (id) on delete set null,
  period_start  date not null,
  period_end    date not null,
  generated_by  uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  check (period_end >= period_start)
);

comment on table public.service_report_generations is
  'Audit trail only — records that a proof-of-service report was generated, by whom, for which site/period. The report content itself is assembled client-side from real data at render time, never stored/duplicated here.';

create index service_report_generations_tenant_id_idx on public.service_report_generations (tenant_id);
create index service_report_generations_site_id_idx on public.service_report_generations (site_id);

create or replace function public.validate_service_report_generation_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: site % does not belong to client %', new.site_id, new.client_id;
  end if;
  return new;
end;
$$;

create trigger service_report_generations_validate_tenant_refs
  before insert on public.service_report_generations
  for each row
  execute function public.validate_service_report_generation_tenant_refs();

alter table public.service_report_generations enable row level security;
alter table public.service_report_generations force row level security;

create policy service_report_generations_select on public.service_report_generations for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or client_id = public.current_client_id()
    or public.is_platform_admin()
  );

-- Insert allowed to anyone who can read the underlying data for that
-- site (internal operations tier or the owning client) — logging that a
-- report was generated is not a privileged action beyond being allowed
-- to view the site in the first place.
create policy service_report_generations_insert on public.service_report_generations for insert to authenticated
  with check (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or client_id = public.current_client_id()
  );

create trigger service_report_generations_audit_log
  after insert on public.service_report_generations
  for each row
  execute function public.audit_log_from_trigger();
