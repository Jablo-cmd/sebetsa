-- Sebetsa Phase Q — Commercial Contract Terms & Version History.
--
-- Extends the existing `contracts` table (Phase C/P) rather than duplicating
-- it: contract_number/dates/status/client/SLA already exist and are
-- untouched. This adds the commercial fields a real cleaning-services
-- contract needs (value, billing, renewal, escalation, responsibility
-- split, service frequency) and a real version-history mechanism so a
-- change to those terms is never a silent overwrite.
--
-- Versioning design: `contract_versions` is populated automatically by a
-- BEFORE UPDATE trigger that diffs OLD vs NEW on the commercial-term
-- columns only (not status, which already has its own transition-guard +
-- generic audit_log coverage) and snapshots the OLD row whenever any of
-- them actually changed — so a manager editing a contract through the
-- existing direct-table-write UI (ContractFormModal, same as today) gets
-- versioning for free, with zero new write path to learn or bypass.
-- change_summary is a deterministic diff of exactly what changed, not a
-- free-text field a caller could omit — "what changed" is always true.

-- ---------------------------------------------------------------------------
-- New enums.

create type public.contract_billing_frequency as enum ('weekly', 'monthly', 'quarterly', 'annually', 'once_off');
create type public.contract_party_responsibility as enum ('contractor', 'client', 'shared');

-- ---------------------------------------------------------------------------
-- Commercial fields on the existing contracts table.

alter table public.contracts
  add column contract_value            numeric(12, 2) check (contract_value is null or contract_value >= 0),
  add column recurring_value           numeric(12, 2) check (recurring_value is null or recurring_value >= 0),
  add column billing_frequency         public.contract_billing_frequency,
  add column payment_terms_days        integer check (payment_terms_days is null or payment_terms_days > 0),
  add column renewal_date              date,
  add column auto_renew                boolean not null default false,
  add column escalation_percentage     numeric(5, 2) check (escalation_percentage is null or escalation_percentage between 0 and 100),
  add column escalation_notes          text,
  add column service_frequency         text,
  add column consumables_responsibility public.contract_party_responsibility,
  add column equipment_responsibility  public.contract_party_responsibility,
  add column labour_notes              text,
  add column notes                     text;

alter table public.contracts
  add constraint contracts_renewal_date_after_start check (renewal_date is null or renewal_date >= start_date);

comment on column public.contracts.contract_value is 'Total contract value (once-off or full term), where applicable — never fabricated: null until a manager enters it.';
comment on column public.contracts.recurring_value is 'Per-billing-cycle value at billing_frequency, where the contract is recurring rather than (or in addition to) a total value.';
comment on column public.contracts.escalation_percentage is 'Configured price-escalation rate applied at renewal (e.g. annual CPI-linked increase) — not computed, a stated contract term.';

-- ---------------------------------------------------------------------------
-- Version history — one row per prior state, the live `contracts` row is
-- always the current version. Populated only by the trigger below, never a
-- direct client write (so history can never be edited or deleted).

create table public.contract_versions (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.organizations (id) on delete cascade,
  contract_id     uuid not null references public.contracts (id) on delete cascade,
  version_number  integer not null check (version_number > 0),
  snapshot        jsonb not null,
  change_summary  text not null,
  changed_by      uuid references public.profiles (id) on delete set null,
  effective_date  date not null default current_date,
  created_at      timestamptz not null default now(),
  unique (contract_id, version_number)
);

comment on table public.contract_versions is
  'Append-only history of prior contract states, auto-populated by contracts_snapshot_version_trigger whenever a commercial-term column changes. snapshot is the full contract row as it was before that change (to_jsonb(old)). Never a client-writable table.';

create index contract_versions_tenant_id_idx on public.contract_versions (tenant_id);
create index contract_versions_contract_id_idx on public.contract_versions (contract_id, version_number);

alter table public.contract_versions enable row level security;
alter table public.contract_versions force row level security;

create policy contract_versions_select on public.contract_versions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

-- No insert/update/delete policy for `authenticated` — written only by the
-- SECURITY DEFINER trigger function below (same bypass-RLS-via-definer
-- pattern already used by audit_log_from_trigger()).

create or replace function public.contracts_snapshot_version()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_version integer;
  v_changes text[] := array[]::text[];
begin
  if new.contract_value is distinct from old.contract_value then
    v_changes := v_changes || format('contract value: %s -> %s', old.contract_value, new.contract_value);
  end if;
  if new.recurring_value is distinct from old.recurring_value then
    v_changes := v_changes || format('recurring value: %s -> %s', old.recurring_value, new.recurring_value);
  end if;
  if new.billing_frequency is distinct from old.billing_frequency then
    v_changes := v_changes || format('billing frequency: %s -> %s', old.billing_frequency, new.billing_frequency);
  end if;
  if new.payment_terms_days is distinct from old.payment_terms_days then
    v_changes := v_changes || format('payment terms: %s -> %s days', old.payment_terms_days, new.payment_terms_days);
  end if;
  if new.renewal_date is distinct from old.renewal_date then
    v_changes := v_changes || format('renewal date: %s -> %s', old.renewal_date, new.renewal_date);
  end if;
  if new.auto_renew is distinct from old.auto_renew then
    v_changes := v_changes || format('auto-renew: %s -> %s', old.auto_renew, new.auto_renew);
  end if;
  if new.escalation_percentage is distinct from old.escalation_percentage then
    v_changes := v_changes || format('escalation: %s%% -> %s%%', old.escalation_percentage, new.escalation_percentage);
  end if;
  if new.escalation_notes is distinct from old.escalation_notes then
    v_changes := v_changes || 'escalation notes updated';
  end if;
  if new.service_frequency is distinct from old.service_frequency then
    v_changes := v_changes || format('service frequency: %s -> %s', old.service_frequency, new.service_frequency);
  end if;
  if new.consumables_responsibility is distinct from old.consumables_responsibility then
    v_changes := v_changes || format('consumables responsibility: %s -> %s', old.consumables_responsibility, new.consumables_responsibility);
  end if;
  if new.equipment_responsibility is distinct from old.equipment_responsibility then
    v_changes := v_changes || format('equipment responsibility: %s -> %s', old.equipment_responsibility, new.equipment_responsibility);
  end if;
  if new.labour_notes is distinct from old.labour_notes then
    v_changes := v_changes || 'labour notes updated';
  end if;
  if new.notes is distinct from old.notes then
    v_changes := v_changes || 'notes updated';
  end if;
  if new.end_date is distinct from old.end_date then
    v_changes := v_changes || format('end date: %s -> %s', old.end_date, new.end_date);
  end if;

  if array_length(v_changes, 1) is null then
    return new;
  end if;

  select coalesce(max(version_number), 0) + 1 into v_next_version
    from public.contract_versions where contract_id = old.id;

  insert into public.contract_versions (tenant_id, contract_id, version_number, snapshot, change_summary, changed_by, effective_date)
  values (old.tenant_id, old.id, v_next_version, to_jsonb(old), array_to_string(v_changes, '; '), auth.uid(), current_date);

  return new;
end;
$$;

comment on function public.contracts_snapshot_version() is
  'BEFORE UPDATE trigger on contracts: snapshots the pre-change row into contract_versions whenever a commercial-term column actually changed. Deliberately excludes status (governed separately by contracts_validate_transition + generic audit_log) to keep version history focused on commercial terms.';

create trigger contracts_snapshot_version_trigger
  before update on public.contracts
  for each row
  execute function public.contracts_snapshot_version();
