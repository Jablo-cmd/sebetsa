-- Sebetsa Phase R — Quoting & Proposals.
--
-- The other half of the revenue engine this codebase's contracts/SLA layer
-- (Phase P) already covers the "governance" half of: QUOTE -> (approval) ->
-- CONTRACT. Nothing quote/proposal-shaped existed anywhere before this —
-- confirmed by repo-wide audit before writing this migration. Line-item
-- totals are DB-generated columns (never client-computed, never trusted
-- from the client); quote-level totals are recomputed server-side by
-- recompute_quote_totals() from the real line items, the same
-- "server always recomputes the number that matters" posture as
-- compute_sla_measurement()/get_command_centre_snapshot().

create type public.quote_status as enum ('draft', 'sent', 'viewed', 'negotiation', 'approved', 'rejected', 'expired', 'cancelled');
create type public.quote_line_category as enum ('labour', 'consumables', 'equipment', 'transport', 'overhead', 'other');

-- ---------------------------------------------------------------------------
create table public.quotes (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  client_id             uuid not null references public.clients (id) on delete cascade,
  site_id               uuid references public.sites (id) on delete set null,
  quote_number          text not null,
  version               integer not null default 1 check (version > 0),
  status                public.quote_status not null default 'draft',
  expiry_date           date,
  discount_amount       numeric(12, 2) not null default 0 check (discount_amount >= 0),
  tax_rate              numeric(5, 2) not null default 15.00 check (tax_rate >= 0 and tax_rate <= 100),
  subtotal              numeric(12, 2) not null default 0,
  tax_amount            numeric(12, 2) not null default 0,
  total_amount          numeric(12, 2) not null default 0,
  notes                 text,
  assumptions           text,
  exclusions            text,
  prepared_by           uuid references public.profiles (id) on delete set null,
  converted_to_contract_id uuid references public.contracts (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (tenant_id, quote_number)
);

comment on table public.quotes is
  'subtotal/tax_amount/total_amount are always written by recompute_quote_totals() from the real line items — never a client-submitted total.';

create index quotes_tenant_id_idx on public.quotes (tenant_id);
create index quotes_client_id_idx on public.quotes (client_id);
create index quotes_status_idx on public.quotes (status);

create trigger quotes_set_updated_at
  before update on public.quotes
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_quote_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger quotes_validate_tenant_refs
  before insert or update on public.quotes
  for each row
  execute function public.validate_quote_tenant_refs();

create or replace function public.quotes_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status in ('sent', 'cancelled'))
    or (old.status = 'sent' and new.status in ('viewed', 'negotiation', 'expired', 'cancelled'))
    or (old.status = 'viewed' and new.status in ('negotiation', 'approved', 'rejected', 'expired', 'cancelled'))
    or (old.status = 'negotiation' and new.status in ('sent', 'approved', 'rejected', 'expired', 'cancelled'))
  ) then
    raise exception 'invalid_transition: cannot move quote from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger quotes_validate_transition_trigger
  before update on public.quotes
  for each row
  execute function public.quotes_validate_transition();

alter table public.quotes enable row level security;
alter table public.quotes force row level security;

create policy quotes_select_within_tenant on public.quotes for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy quotes_write_by_manager on public.quotes for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger quotes_audit_log
  after insert or update on public.quotes
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create table public.quote_line_items (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  quote_id      uuid not null references public.quotes (id) on delete cascade,
  category      public.quote_line_category not null default 'other',
  description   text not null check (char_length(description) > 0),
  quantity      numeric(10, 2) not null check (quantity > 0),
  unit_rate     numeric(12, 2) not null check (unit_rate >= 0),
  line_total    numeric(14, 2) generated always as (quantity * unit_rate) stored,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on column public.quote_line_items.line_total is
  'DB-generated (quantity * unit_rate) — structurally impossible for a line total to drift from its inputs.';

create index quote_line_items_tenant_id_idx on public.quote_line_items (tenant_id);
create index quote_line_items_quote_id_idx on public.quote_line_items (quote_id, sort_order);

create trigger quote_line_items_set_updated_at
  before update on public.quote_line_items
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_quote_line_item_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.quotes where id = new.quote_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: quote % does not belong to tenant %', new.quote_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger quote_line_items_validate_tenant_refs
  before insert or update on public.quote_line_items
  for each row
  execute function public.validate_quote_line_item_tenant_refs();

alter table public.quote_line_items enable row level security;
alter table public.quote_line_items force row level security;

create policy quote_line_items_select_within_tenant on public.quote_line_items for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy quote_line_items_write_by_manager on public.quote_line_items for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger quote_line_items_audit_log
  after insert or update on public.quote_line_items
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- recompute_quote_totals: the server always recomputes subtotal/tax/total
-- from the real line items — a client can never submit a total directly.

create or replace function public.recompute_quote_totals(p_quote_id uuid)
returns public.quotes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quotes;
  v_subtotal numeric(12, 2);
  v_tax numeric(12, 2);
  v_total numeric(12, 2);
begin
  select * into v_quote from public.quotes where id = p_quote_id;
  if not found then
    raise exception 'not_found: no quote %', p_quote_id;
  end if;

  if not public.can_manage_org_structure(v_quote.tenant_id) then
    raise exception 'insufficient_privilege: cannot recompute totals for this tenant';
  end if;

  select coalesce(sum(line_total), 0) into v_subtotal from public.quote_line_items where quote_id = p_quote_id;
  v_tax := round((v_subtotal - v_quote.discount_amount) * v_quote.tax_rate / 100.0, 2);
  v_total := v_subtotal - v_quote.discount_amount + v_tax;

  update public.quotes
    set subtotal = v_subtotal, tax_amount = v_tax, total_amount = v_total
    where id = p_quote_id
    returning * into v_quote;

  perform public.write_audit_log(v_quote.tenant_id, auth.uid(), 'quote_totals_recomputed', 'quotes', v_quote.id, null,
    jsonb_build_object('subtotal', v_subtotal, 'tax_amount', v_tax, 'total_amount', v_total));

  return v_quote;
end;
$$;

comment on function public.recompute_quote_totals(uuid) is
  'The only way subtotal/tax_amount/total_amount on a quote ever change — always derived from real quote_line_items rows, never a client-submitted figure.';

revoke execute on function public.recompute_quote_totals(uuid) from public, anon;
grant execute on function public.recompute_quote_totals(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- convert_quote_to_contract: the controlled QUOTE -> CONTRACT conversion.
-- Only an approved quote converts; only once (converted_to_contract_id is
-- set exactly once, checked here); the new contract's value is the quote's
-- own server-computed total_amount, never re-entered by hand.

create or replace function public.convert_quote_to_contract(
  p_quote_id uuid,
  p_contract_number text,
  p_start_date date
)
returns public.contracts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quotes;
  v_contract public.contracts;
begin
  select * into v_quote from public.quotes where id = p_quote_id;
  if not found then
    raise exception 'not_found: no quote %', p_quote_id;
  end if;

  if not public.can_manage_org_structure(v_quote.tenant_id) then
    raise exception 'insufficient_privilege: cannot convert this quote';
  end if;

  if v_quote.status <> 'approved' then
    raise exception 'invalid_state: only an approved quote can be converted to a contract (current status: %)', v_quote.status;
  end if;

  if v_quote.converted_to_contract_id is not null then
    raise exception 'already_converted: quote % was already converted to contract %', p_quote_id, v_quote.converted_to_contract_id;
  end if;

  insert into public.contracts (tenant_id, client_id, contract_number, start_date, status, contract_value, notes)
  values (v_quote.tenant_id, v_quote.client_id, p_contract_number, p_start_date, 'draft', v_quote.total_amount, v_quote.notes)
  returning * into v_contract;

  if v_quote.site_id is not null then
    insert into public.contract_sites (contract_id, site_id, tenant_id)
    values (v_contract.id, v_quote.site_id, v_quote.tenant_id);
  end if;

  update public.quotes set converted_to_contract_id = v_contract.id where id = p_quote_id;

  perform public.write_audit_log(v_quote.tenant_id, auth.uid(), 'quote_converted_to_contract', 'quotes', v_quote.id, null,
    jsonb_build_object('contract_id', v_contract.id));
  perform public.write_audit_log(v_contract.tenant_id, auth.uid(), 'contract_created_from_quote', 'contracts', v_contract.id, null,
    jsonb_build_object('quote_id', v_quote.id));

  return v_contract;
end;
$$;

comment on function public.convert_quote_to_contract(uuid, text, date) is
  'The controlled QUOTE -> CONTRACT boundary: only an approved, not-yet-converted quote can convert, exactly once, with the new contract''s value taken from the quote''s own server-computed total — never re-typed, never duplicated.';

revoke execute on function public.convert_quote_to_contract(uuid, text, date) from public, anon;
grant execute on function public.convert_quote_to_contract(uuid, text, date) to authenticated;
