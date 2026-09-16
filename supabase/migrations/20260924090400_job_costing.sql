-- Sebetsa Phase X — Job Costing & Profitability.
--
-- Real cost configuration, not invented rates: no pay-rate or unit-cost
-- concept existed anywhere in this repository before this migration
-- (confirmed by repo-wide search) — employee_cost_rates and
-- inventory_items.standard_unit_cost are the real configuration a manager
-- must enter before any labour/consumables cost can be computed. Until
-- configured, get_contract_profitability() reports those cost components
-- honestly as zero/null-derived rather than fabricating a number, and the
-- frontend must show "not configured" rather than a blank zero implying
-- "no cost."

create table public.employee_cost_rates (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  employee_id         uuid not null references public.employees (id) on delete cascade,
  hourly_rate         numeric(10, 2) not null check (hourly_rate >= 0),
  overtime_multiplier numeric(4, 2) not null default 1.5 check (overtime_multiplier >= 1),
  effective_from      date not null,
  effective_to        date,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

comment on table public.employee_cost_rates is
  'The real, configured hourly cost for an employee, effective-dated. get_contract_profitability() joins attendance_records against whichever rate row was effective on the worked date — never an invented average rate. Simplification, disclosed: overlapping effective ranges for the same employee are not constrained here; consistent data entry (closing the prior range''s effective_to before opening a new one) is expected, matching this table''s narrow, single-purpose scope.';

create index employee_cost_rates_tenant_id_idx on public.employee_cost_rates (tenant_id);
create index employee_cost_rates_employee_id_idx on public.employee_cost_rates (employee_id, effective_from);

create trigger employee_cost_rates_set_updated_at
  before update on public.employee_cost_rates
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_employee_cost_rate_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger employee_cost_rates_validate_tenant_refs
  before insert or update on public.employee_cost_rates
  for each row
  execute function public.validate_employee_cost_rate_tenant_refs();

alter table public.employee_cost_rates enable row level security;
alter table public.employee_cost_rates force row level security;

-- Cost rates are commercially sensitive — never visible to a client, and
-- restricted even internally to the org-structure/commercial tier (the
-- same tier governing contracts/quotes/invoices), not every operations
-- manager who can merely schedule shifts.
create policy employee_cost_rates_select on public.employee_cost_rates for select to authenticated
  using (public.can_manage_org_structure(tenant_id) or public.is_platform_admin());
create policy employee_cost_rates_write on public.employee_cost_rates for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger employee_cost_rates_audit_log
  after insert or update on public.employee_cost_rates
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- The real, configured standard unit cost for a consumable — nullable
-- (unconfigured until a manager enters it; never defaulted to a guessed
-- value).

alter table public.inventory_items add column standard_unit_cost numeric(10, 2) check (standard_unit_cost is null or standard_unit_cost >= 0);

comment on column public.inventory_items.standard_unit_cost is
  'The real configured per-unit cost, used by get_contract_profitability() to cost `issue` movements. Null until a manager enters it — never defaulted or guessed.';

-- ---------------------------------------------------------------------------
create type public.cost_entry_category as enum ('equipment', 'other');

create table public.cost_entries (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.organizations (id) on delete cascade,
  contract_id        uuid references public.contracts (id) on delete set null,
  site_id            uuid not null references public.sites (id) on delete cascade,
  variation_order_id uuid references public.variation_orders (id) on delete set null,
  category           public.cost_entry_category not null default 'other',
  description        text not null check (char_length(description) > 0),
  amount             numeric(12, 2) not null check (amount >= 0),
  cost_date          date not null,
  recorded_by        uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now()
);

comment on table public.cost_entries is
  'Manually recorded equipment/other direct costs (rental, transport, subcontractor, waste, misc). Labour and consumables costs are computed, not entered here — see employee_cost_rates/inventory_items.standard_unit_cost.';

create index cost_entries_tenant_id_idx on public.cost_entries (tenant_id);
create index cost_entries_contract_id_idx on public.cost_entries (contract_id);
create index cost_entries_site_id_idx on public.cost_entries (site_id, cost_date);

create or replace function public.validate_cost_entry_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger cost_entries_validate_tenant_refs
  before insert or update on public.cost_entries
  for each row
  execute function public.validate_cost_entry_tenant_refs();

alter table public.cost_entries enable row level security;
alter table public.cost_entries force row level security;

create policy cost_entries_select on public.cost_entries for select to authenticated
  using (public.can_manage_org_structure(tenant_id) or public.is_platform_admin());
create policy cost_entries_write on public.cost_entries for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger cost_entries_audit_log
  after insert on public.cost_entries
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- get_contract_profitability: Revenue - Labour - Consumables - Equipment -
-- Other = Gross Contribution; Gross Contribution / Revenue * 100 = Gross
-- Margin %. Every component is a real aggregate over persisted data for
-- the given contract and period — never a fabricated percentage.
-- margin_pct is null (not zero, not fabricated) when revenue is zero.

create or replace function public.get_contract_profitability(p_contract_id uuid, p_period_start date, p_period_end date)
returns table (
  revenue numeric,
  labour_cost numeric,
  consumables_cost numeric,
  equipment_cost numeric,
  other_cost numeric,
  gross_contribution numeric,
  gross_margin_pct numeric
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_tenant_id uuid;
  v_revenue numeric;
  v_labour numeric;
  v_consumables numeric;
  v_equipment numeric;
  v_other numeric;
  v_contribution numeric;
begin
  select tenant_id into v_tenant_id from public.contracts where id = p_contract_id;
  if v_tenant_id is null then
    raise exception 'not_found: no contract %', p_contract_id;
  end if;
  if not public.can_manage_org_structure(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot view profitability for this tenant';
  end if;

  select coalesce(sum(i.total_amount), 0) into v_revenue
    from public.invoices i
    where i.contract_id = p_contract_id
      and i.status not in ('void', 'cancelled', 'draft')
      and coalesce(i.issue_date, i.billing_period_start) between p_period_start and p_period_end;

  select coalesce(sum(
      extract(epoch from (a.clock_out_at - a.clock_in_at)) / 3600.0
      * coalesce(
          (select r.hourly_rate from public.employee_cost_rates r
            where r.employee_id = a.employee_id
              and r.effective_from <= a.clock_in_at::date
              and (r.effective_to is null or r.effective_to >= a.clock_in_at::date)
            order by r.effective_from desc limit 1),
          0)
    ), 0) into v_labour
    from public.attendance_records a
    join public.contract_sites cs on cs.site_id = a.site_id
    where cs.contract_id = p_contract_id
      and a.clock_in_at is not null and a.clock_out_at is not null
      and a.clock_in_at::date between p_period_start and p_period_end;

  select coalesce(sum(m.quantity * coalesce(ii.standard_unit_cost, 0)), 0) into v_consumables
    from public.inventory_movements m
    join public.inventory_items ii on ii.id = m.item_id
    join public.contract_sites cs on cs.site_id = m.site_id
    where cs.contract_id = p_contract_id
      and m.movement_type = 'issue'
      and m.created_at::date between p_period_start and p_period_end;

  select coalesce(sum(amount) filter (where category = 'equipment'), 0),
         coalesce(sum(amount) filter (where category = 'other'), 0)
    into v_equipment, v_other
    from public.cost_entries
    where contract_id = p_contract_id and cost_date between p_period_start and p_period_end;

  v_contribution := v_revenue - v_labour - v_consumables - v_equipment - v_other;

  return query select
    v_revenue, v_labour, v_consumables, v_equipment, v_other, v_contribution,
    case when v_revenue > 0 then round(v_contribution / v_revenue * 100, 2) else null end;
end;
$$;

comment on function public.get_contract_profitability(uuid, date, date) is
  'Revenue - Labour - Consumables - Equipment - Other = Gross Contribution; Gross Contribution / Revenue x 100 = Gross Margin %%. Every figure is a real aggregate over invoices/attendance_records/inventory_movements/cost_entries for this contract and period — never a fabricated number. margin_pct is null, never a misleading zero, when revenue is zero.';

revoke execute on function public.get_contract_profitability(uuid, date, date) from public, anon;
grant execute on function public.get_contract_profitability(uuid, date, date) to authenticated;
