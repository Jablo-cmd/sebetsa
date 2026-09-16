-- Sebetsa Phase V — Billing, Invoicing & Payment Recording.
--
-- One of the most important pieces of this sprint: a real, server-
-- authoritative invoice domain. Line totals are DB-generated columns
-- (quantity * unit_price — never client-writable, same pattern as
-- quote_line_items). Invoice numbers are assigned by an atomic per-tenant
-- counter (a single UPSERT statement, never a check-then-insert race).
-- record_payment() locks the invoice row (SELECT ... FOR UPDATE) before
-- computing amount_paid/status, so two concurrent payments against the
-- same invoice can never both pass an overpayment check.
--
-- NO payment gateway is implemented or claimed. This is payment
-- RECORDING infrastructure — a manual "a payment of X was received on Y"
-- entry — never online payment processing.

create type public.invoice_status as enum ('draft', 'issued', 'partially_paid', 'paid', 'void', 'cancelled');
create type public.invoice_source as enum ('contract_billing', 'variation', 'manual');

-- ---------------------------------------------------------------------------
-- Atomic per-tenant invoice numbering. A single UPSERT statement — no
-- separate "read the last number, then insert" step exists anywhere.

create table public.invoice_number_counters (
  tenant_id   uuid primary key references public.organizations (id) on delete cascade,
  last_number integer not null default 0 check (last_number >= 0)
);

comment on table public.invoice_number_counters is
  'One row per tenant. next_invoice_number() increments this with a single atomic UPSERT — concurrency-safe by Postgres row-lock semantics, never a check-then-insert race.';

create or replace function public.next_invoice_number(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
begin
  insert into public.invoice_number_counters (tenant_id, last_number)
  values (p_tenant_id, 1)
  on conflict (tenant_id) do update set last_number = public.invoice_number_counters.last_number + 1
  returning last_number into v_seq;

  return 'INV-' || to_char(now(), 'YYYY') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;

revoke execute on function public.next_invoice_number(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
create table public.invoices (
  id                   uuid primary key default gen_random_uuid(),
  tenant_id            uuid not null references public.organizations (id) on delete cascade,
  client_id            uuid not null references public.clients (id) on delete cascade,
  contract_id          uuid references public.contracts (id) on delete set null,
  site_id              uuid references public.sites (id) on delete set null,
  variation_order_id   uuid references public.variation_orders (id) on delete set null,
  invoice_number       text not null,
  source               public.invoice_source not null default 'manual',
  billing_period_start date,
  billing_period_end   date,
  status               public.invoice_status not null default 'draft',
  currency             text not null default 'ZAR',
  tax_rate             numeric(5, 2) not null default 15.00 check (tax_rate >= 0 and tax_rate <= 100),
  subtotal             numeric(12, 2) not null default 0,
  tax_amount           numeric(12, 2) not null default 0,
  total_amount         numeric(12, 2) not null default 0,
  amount_paid          numeric(12, 2) not null default 0 check (amount_paid >= 0),
  amount_outstanding   numeric(12, 2) generated always as (total_amount - amount_paid) stored,
  issue_date           date,
  due_date             date,
  notes                text,
  void_reason          text,
  created_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (tenant_id, invoice_number),
  check (billing_period_end is null or billing_period_start is null or billing_period_end >= billing_period_start),
  check (due_date is null or issue_date is null or due_date >= issue_date)
);

comment on table public.invoices is
  'subtotal/tax_amount/total_amount are always written by recompute_invoice_totals() from the real invoice_lines — never a client-submitted total. amount_paid is always written by record_payment() from the real payments rows.';

create index invoices_tenant_id_idx on public.invoices (tenant_id);
create index invoices_client_id_idx on public.invoices (client_id);
create index invoices_contract_id_idx on public.invoices (contract_id);
create index invoices_status_idx on public.invoices (status);
create index invoices_due_date_idx on public.invoices (due_date);

-- Never double-bill the same contract for the same billing period.
create unique index invoices_contract_billing_period_uidx on public.invoices (contract_id, billing_period_start, billing_period_end)
  where source = 'contract_billing' and status not in ('void', 'cancelled');

create trigger invoices_set_updated_at
  before update on public.invoices
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_invoice_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: contract % does not belong to client %', new.contract_id, new.client_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.variation_order_id is not null and not exists (select 1 from public.variation_orders where id = new.variation_order_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: variation order % does not belong to client %', new.variation_order_id, new.client_id;
  end if;
  return new;
end;
$$;

create trigger invoices_validate_tenant_refs
  before insert or update on public.invoices
  for each row
  execute function public.validate_invoice_tenant_refs();

create or replace function public.invoices_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status in ('issued', 'cancelled'))
    or (old.status = 'issued' and new.status in ('partially_paid', 'paid', 'void'))
    or (old.status = 'partially_paid' and new.status in ('paid', 'void'))
  ) then
    raise exception 'invalid_transition: cannot move invoice from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger invoices_validate_transition_trigger
  before update on public.invoices
  for each row
  execute function public.invoices_validate_transition();

alter table public.invoices enable row level security;
alter table public.invoices force row level security;

create policy invoices_select on public.invoices for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or client_id = public.current_client_id()
    or public.is_platform_admin()
  );

-- UPDATE only, never INSERT — invoice_number is safely assigned only by
-- next_invoice_number() inside create_draft_invoice()/
-- generate_contract_billing_invoice()/create_variation_invoice(), which
-- bypass RLS via the SECURITY DEFINER owner mechanism (same as
-- contract_versions/audit_log). A direct client INSERT is never possible,
-- so a caller can never supply their own invoice_number.
create policy invoices_update_by_manager on public.invoices for update to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

-- Protection on top of the row-level policy above: even a manager who may
-- UPDATE an invoice row at all can never directly write its server-
-- computed financial columns. A column-level REVOKE does NOT work here —
-- 00_auth_stub.sql's `alter default privileges ... grant all on tables to
-- authenticated` (mirroring real Supabase projects) grants a TABLE-LEVEL
-- UPDATE at CREATE TABLE time, and a table-level grant supersedes any
-- column-level REVOKE of the same privilege (the same gotcha already
-- documented against profiles.role in 20260911100300). The mechanism
-- that actually works — proven by profiles.prevent_direct_role_change()
-- — is a BEFORE UPDATE trigger gated by a transaction-local flag that
-- only the trusted RPCs set immediately before their own UPDATE.
create or replace function public.prevent_direct_invoice_financial_change()
returns trigger
language plpgsql
as $$
begin
  if (
    new.subtotal is distinct from old.subtotal
    or new.tax_amount is distinct from old.tax_amount
    or new.total_amount is distinct from old.total_amount
    or new.amount_paid is distinct from old.amount_paid
    or new.invoice_number is distinct from old.invoice_number
  ) and coalesce(current_setting('app.allow_financial_recompute', true), '') <> 'true' then
    raise exception 'insufficient_privilege: invoice subtotal/tax_amount/total_amount/amount_paid/invoice_number can only be changed via recompute_invoice_totals()/issue_invoice()/record_payment()';
  end if;
  return new;
end;
$$;

create trigger invoices_prevent_direct_financial_change
  before update on public.invoices
  for each row
  execute function public.prevent_direct_invoice_financial_change();

create trigger invoices_audit_log
  after insert or update on public.invoices
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create table public.invoice_lines (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.organizations (id) on delete cascade,
  invoice_id   uuid not null references public.invoices (id) on delete cascade,
  description  text not null check (char_length(description) > 0),
  quantity     numeric(10, 2) not null check (quantity > 0),
  unit_price   numeric(12, 2) not null check (unit_price >= 0),
  line_total   numeric(14, 2) generated always as (quantity * unit_price) stored,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on column public.invoice_lines.line_total is
  'DB-generated (quantity * unit_price) — structurally impossible for a line total to be forged from the client, same pattern as quote_line_items.line_total.';

create index invoice_lines_tenant_id_idx on public.invoice_lines (tenant_id);
create index invoice_lines_invoice_id_idx on public.invoice_lines (invoice_id, sort_order);

create trigger invoice_lines_set_updated_at
  before update on public.invoice_lines
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_invoice_line_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.invoices where id = new.invoice_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: invoice % does not belong to tenant %', new.invoice_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger invoice_lines_validate_tenant_refs
  before insert or update on public.invoice_lines
  for each row
  execute function public.validate_invoice_line_tenant_refs();

alter table public.invoice_lines enable row level security;
alter table public.invoice_lines force row level security;

create policy invoice_lines_select on public.invoice_lines for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or exists (select 1 from public.invoices i where i.id = invoice_lines.invoice_id and i.client_id = public.current_client_id())
    or public.is_platform_admin()
  );

create policy invoice_lines_write_by_manager on public.invoice_lines for all to authenticated
  using (public.can_manage_org_structure(tenant_id))
  with check (public.can_manage_org_structure(tenant_id));

create trigger invoice_lines_audit_log
  after insert or update on public.invoice_lines
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create table public.payments (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.organizations (id) on delete cascade,
  invoice_id   uuid not null references public.invoices (id) on delete cascade,
  amount       numeric(12, 2) not null check (amount > 0),
  payment_date date not null,
  method       text,
  reference    text,
  notes        text,
  recorded_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);

comment on table public.payments is
  'Manual payment RECORDING only — no payment gateway. Append-only; a mistaken entry is corrected by recording a new row and adjusting via void_invoice()/manager review, never a silent update, so the payment history is always a true record of what was recorded and when.';

create index payments_tenant_id_idx on public.payments (tenant_id);
create index payments_invoice_id_idx on public.payments (invoice_id);

create or replace function public.validate_payment_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.invoices where id = new.invoice_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: invoice % does not belong to tenant %', new.invoice_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger payments_validate_tenant_refs
  before insert on public.payments
  for each row
  execute function public.validate_payment_tenant_refs();

alter table public.payments enable row level security;
alter table public.payments force row level security;

create policy payments_select on public.payments for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or exists (select 1 from public.invoices i where i.id = payments.invoice_id and i.client_id = public.current_client_id())
    or public.is_platform_admin()
  );

-- No direct client write policy — record_payment() only, so amount_paid
-- on the parent invoice can never drift from the real payments rows.

create trigger payments_audit_log
  after insert on public.payments
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create or replace function public.recompute_invoice_totals(p_invoice_id uuid)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_subtotal numeric(12, 2);
  v_tax numeric(12, 2);
  v_total numeric(12, 2);
begin
  select * into v_invoice from public.invoices where id = p_invoice_id;
  if not found then
    raise exception 'not_found: no invoice %', p_invoice_id;
  end if;

  if not public.can_manage_org_structure(v_invoice.tenant_id) then
    raise exception 'insufficient_privilege: cannot recompute totals for this tenant';
  end if;

  select coalesce(sum(line_total), 0) into v_subtotal from public.invoice_lines where invoice_id = p_invoice_id;
  v_tax := round(v_subtotal * v_invoice.tax_rate / 100.0, 2);
  v_total := v_subtotal + v_tax;

  perform set_config('app.allow_financial_recompute', 'true', true);
  update public.invoices set subtotal = v_subtotal, tax_amount = v_tax, total_amount = v_total
    where id = p_invoice_id
    returning * into v_invoice;
  perform set_config('app.allow_financial_recompute', 'false', true);

  perform public.write_audit_log(v_invoice.tenant_id, auth.uid(), 'invoice_totals_recomputed', 'invoices', v_invoice.id, null,
    jsonb_build_object('subtotal', v_subtotal, 'tax_amount', v_tax, 'total_amount', v_total));

  return v_invoice;
end;
$$;

revoke execute on function public.recompute_invoice_totals(uuid) from public, anon;
grant execute on function public.recompute_invoice_totals(uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.issue_invoice(p_invoice_id uuid, p_issue_date date, p_due_date date)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
begin
  select * into v_invoice from public.invoices where id = p_invoice_id;
  if not found then
    raise exception 'not_found: no invoice %', p_invoice_id;
  end if;
  if not public.can_manage_org_structure(v_invoice.tenant_id) then
    raise exception 'insufficient_privilege: cannot issue this invoice';
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'invalid_state: invoice % is not a draft (status: %)', p_invoice_id, v_invoice.status;
  end if;
  if v_invoice.total_amount <= 0 then
    raise exception 'invalid_state: invoice % has no line items to issue', p_invoice_id;
  end if;

  perform set_config('app.allow_financial_recompute', 'true', true);
  update public.invoices
    set status = 'issued', issue_date = p_issue_date, due_date = p_due_date, invoice_number = coalesce(invoice_number, public.next_invoice_number(v_invoice.tenant_id))
    where id = p_invoice_id
    returning * into v_invoice;
  perform set_config('app.allow_financial_recompute', 'false', true);

  return v_invoice;
end;
$$;

revoke execute on function public.issue_invoice(uuid, date, date) from public, anon;
grant execute on function public.issue_invoice(uuid, date, date) to authenticated;

create or replace function public.void_invoice(p_invoice_id uuid, p_reason text)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
begin
  select * into v_invoice from public.invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'not_found: no invoice %', p_invoice_id;
  end if;
  if not public.can_manage_org_structure(v_invoice.tenant_id) then
    raise exception 'insufficient_privilege: cannot void this invoice';
  end if;
  if v_invoice.status not in ('issued', 'partially_paid') then
    raise exception 'invalid_state: only an issued or partially-paid invoice can be voided (status: %)', v_invoice.status;
  end if;

  update public.invoices set status = 'void', void_reason = p_reason where id = p_invoice_id returning * into v_invoice;

  perform public.write_audit_log(v_invoice.tenant_id, auth.uid(), 'invoice_voided', 'invoices', p_invoice_id, null, jsonb_build_object('reason', p_reason));

  return v_invoice;
end;
$$;

revoke execute on function public.void_invoice(uuid, text) from public, anon;
grant execute on function public.void_invoice(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- record_payment: locks the invoice row before computing amount_paid, so
-- two concurrent payments can never both pass the overpayment check —
-- the second call blocks until the first commits, then sees the updated
-- amount_paid.

create or replace function public.record_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_method text default null,
  p_reference text default null,
  p_notes text default null
)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_new_paid numeric(12, 2);
begin
  select * into v_invoice from public.invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'not_found: no invoice %', p_invoice_id;
  end if;
  if not public.can_manage_org_structure(v_invoice.tenant_id) then
    raise exception 'insufficient_privilege: cannot record a payment for this tenant';
  end if;
  if v_invoice.status not in ('issued', 'partially_paid') then
    raise exception 'invalid_state: invoice % is not open for payment (status: %)', p_invoice_id, v_invoice.status;
  end if;

  v_new_paid := v_invoice.amount_paid + p_amount;
  if v_new_paid > v_invoice.total_amount then
    raise exception 'overpayment_not_allowed: payment of % would exceed the outstanding balance of %', p_amount, v_invoice.total_amount - v_invoice.amount_paid;
  end if;

  insert into public.payments (tenant_id, invoice_id, amount, payment_date, method, reference, notes, recorded_by)
  values (v_invoice.tenant_id, p_invoice_id, p_amount, p_payment_date, p_method, p_reference, p_notes, auth.uid());

  perform set_config('app.allow_financial_recompute', 'true', true);
  update public.invoices
    set amount_paid = v_new_paid, status = (case when v_new_paid >= total_amount then 'paid' else 'partially_paid' end)::public.invoice_status
    where id = p_invoice_id
    returning * into v_invoice;
  perform set_config('app.allow_financial_recompute', 'false', true);

  perform public.write_audit_log(v_invoice.tenant_id, auth.uid(), 'payment_recorded', 'invoices', p_invoice_id, null,
    jsonb_build_object('amount', p_amount, 'new_status', v_invoice.status));

  return v_invoice;
end;
$$;

comment on function public.record_payment(uuid, numeric, date, text, text, text) is
  'The only way amount_paid/status change on an invoice. Locks the invoice row first (SELECT ... FOR UPDATE) so concurrent payments serialize instead of racing past the overpayment check.';

revoke execute on function public.record_payment(uuid, numeric, date, text, text, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, date, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- create_draft_invoice: the manual-invoice path. invoice_number is NOT
-- NULL with no default — a plain client table INSERT can never create an
-- invoice row (RLS's write policy would allow it, but the missing number
-- fails the NOT NULL constraint), so every invoice, manual or generated,
-- is always number-assigned through this RPC layer, never bypassed.

create or replace function public.create_draft_invoice(
  p_client_id uuid,
  p_contract_id uuid default null,
  p_site_id uuid default null,
  p_tax_rate numeric default 15.00,
  p_notes text default null
)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.invoices;
begin
  select tenant_id into v_tenant_id from public.clients where id = p_client_id;
  if v_tenant_id is null then
    raise exception 'not_found: no client %', p_client_id;
  end if;
  if not public.can_manage_org_structure(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot create an invoice for this tenant';
  end if;

  insert into public.invoices (tenant_id, client_id, contract_id, site_id, invoice_number, source, tax_rate, notes)
  values (v_tenant_id, p_client_id, p_contract_id, p_site_id, public.next_invoice_number(v_tenant_id), 'manual', p_tax_rate, p_notes)
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.create_draft_invoice(uuid, uuid, uuid, numeric, text) from public, anon;
grant execute on function public.create_draft_invoice(uuid, uuid, uuid, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- generate_contract_billing_invoice: recurring-contract billing, driven by
-- the contract's own persisted commercial terms (Phase Q) — never an
-- arbitrary frontend-entered amount. The partial unique index above makes
-- a duplicate call for the same (contract_id, period) fail cleanly rather
-- than double-billing.

create or replace function public.generate_contract_billing_invoice(
  p_contract_id uuid,
  p_billing_period_start date,
  p_billing_period_end date
)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contract public.contracts;
  v_invoice public.invoices;
begin
  select * into v_contract from public.contracts where id = p_contract_id;
  if not found then
    raise exception 'not_found: no contract %', p_contract_id;
  end if;
  if not public.can_manage_org_structure(v_contract.tenant_id) then
    raise exception 'insufficient_privilege: cannot bill this contract';
  end if;
  if v_contract.recurring_value is null or v_contract.recurring_value <= 0 then
    raise exception 'missing_billing_terms: contract % has no recurring_value configured to bill', p_contract_id;
  end if;

  insert into public.invoices (tenant_id, client_id, contract_id, invoice_number, source, billing_period_start, billing_period_end)
  values (v_contract.tenant_id, v_contract.client_id, p_contract_id, public.next_invoice_number(v_contract.tenant_id), 'contract_billing', p_billing_period_start, p_billing_period_end)
  returning * into v_invoice;

  insert into public.invoice_lines (tenant_id, invoice_id, description, quantity, unit_price)
  values (v_contract.tenant_id, v_invoice.id,
    'Contract services (' || coalesce(v_contract.billing_frequency::text, 'recurring') || ') — ' || p_billing_period_start || ' to ' || p_billing_period_end,
    1, v_contract.recurring_value);

  return public.recompute_invoice_totals(v_invoice.id);
end;
$$;

comment on function public.generate_contract_billing_invoice(uuid, date, date) is
  'A real invoice generated from the contract''s own persisted recurring_value — never a manually re-typed figure. The unique index on (contract_id, billing_period_start, billing_period_end) for source=contract_billing rows makes calling this twice for the same period fail with a clean constraint violation rather than silently double-billing.';

revoke execute on function public.generate_contract_billing_invoice(uuid, date, date) from public, anon;
grant execute on function public.generate_contract_billing_invoice(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- create_variation_invoice: bills a completed variation directly from its
-- own quote's server-computed total — never re-typed.

create or replace function public.create_variation_invoice(p_variation_id uuid)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variation public.variation_orders;
  v_quote public.quotes;
  v_invoice public.invoices;
begin
  select * into v_variation from public.variation_orders where id = p_variation_id;
  if not found then
    raise exception 'not_found: no variation order %', p_variation_id;
  end if;
  if not public.can_manage_org_structure(v_variation.tenant_id) then
    raise exception 'insufficient_privilege: cannot invoice this variation';
  end if;
  if v_variation.status <> 'completed' then
    raise exception 'invalid_state: variation % is not completed (status: %)', p_variation_id, v_variation.status;
  end if;
  if v_variation.quote_id is null then
    raise exception 'missing_quote: variation % has no linked quote to bill from', p_variation_id;
  end if;

  select * into v_quote from public.quotes where id = v_variation.quote_id;

  insert into public.invoices (tenant_id, client_id, contract_id, site_id, variation_order_id, invoice_number, source)
  values (v_variation.tenant_id, v_variation.client_id, v_variation.contract_id, v_variation.site_id, v_variation.id, public.next_invoice_number(v_variation.tenant_id), 'variation')
  returning * into v_invoice;

  insert into public.invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, sort_order)
  select v_variation.tenant_id, v_invoice.id, description, quantity, unit_rate, sort_order
  from public.quote_line_items where quote_id = v_quote.id;

  update public.variation_orders set status = 'invoiced' where id = p_variation_id;

  return public.recompute_invoice_totals(v_invoice.id);
end;
$$;

comment on function public.create_variation_invoice(uuid) is
  'Copies the variation''s own approved quote line items into a real invoice — the same server-computed figures the client already approved, never re-typed. Only a completed variation with a linked quote can be invoiced; moves the variation to invoiced, its final state.';

revoke execute on function public.create_variation_invoice(uuid) from public, anon;
grant execute on function public.create_variation_invoice(uuid) to authenticated;
