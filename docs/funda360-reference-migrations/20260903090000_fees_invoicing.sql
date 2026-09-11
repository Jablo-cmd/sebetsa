-- Fees Domain Extension — Invoicing, Payment Allocation, Receipts, VAT
--
-- Additive only. The existing ledger model (20260823120000_fees_domain.sql:
-- "balance is derived by aggregation at query time, not stored") is
-- preserved exactly. This migration does NOT introduce a competing
-- money-of-record: `learner_fee_charges` / `learner_fee_payments` remain
-- the single source of truth for every rand. What is added is a
-- *documentary and attribution* layer on top of that ledger:
--
--   * invoices            — a numbered, dated, lockable grouping of charges
--                           that already exist as ledger rows. An invoice's
--                           subtotal is always sum(its active charges);
--                           issuing it snapshots that figure + VAT + total
--                           for the PDF and for historical integrity.
--   * payment allocations — optionally attribute portions of a payment to
--                           specific invoices, so an invoice can have its
--                           own paid/outstanding position. Unallocated
--                           payment amount is simply an account credit,
--                           exactly as before (the school-wide and
--                           per-learner derived balance math in
--                           features/fees/utils/calculations.ts is
--                           unchanged and still authoritative).
--   * fee_receipts        — a numbered acknowledgement of one payment.
--   * VAT config          — per-school, defaulting to 0 (SA school fees are
--                           generally VAT-exempt; the field exists for the
--                           minority of taxable supplies — see spec 4.D).
--
-- RBAC: reuses can_view_learner_financial() / can_manage_learner_financial()
-- verbatim — the actor set for "who may see / manage a learner's fee
-- position" does not change because a new row type was added to it.
-- Guardians get SELECT on their own child's invoices / allocations /
-- receipts, mirroring learner_fee_charges_select_for_guardians.
--
-- SECURITY DEFINER: numbering, issuing, voiding, allocation and receipt
-- creation all go through SECURITY DEFINER RPCs — never direct client
-- writes — for the same reasons the bank-reconciliation migration
-- (20260829290000) documents: these transitions touch multiple rows
-- atomically, enforce cross-row invariants (allocation never exceeds the
-- payment or the invoice), and consume a gap-free per-school sequence.
-- Direct client writes to the protected columns are blocked by trigger,
-- exactly as learner_fee_payments.reconciled_at is.

-- ---------------------------------------------------------------------------
-- 0. Per-school billing configuration.

alter table public.schools
  add column if not exists vat_registered      boolean not null default false,
  add column if not exists vat_number          text,
  add column if not exists vat_rate            numeric(5, 2) not null default 0
    check (vat_rate >= 0 and vat_rate <= 100),
  add column if not exists invoice_number_prefix text not null default 'INV',
  add column if not exists receipt_number_prefix text not null default 'RCT',
  add column if not exists invoice_due_days     integer not null default 30
    check (invoice_due_days >= 0 and invoice_due_days <= 365),
  add column if not exists invoice_footer_note  text,
  add column if not exists banking_details      text;

comment on column public.schools.vat_rate is 'Default VAT percentage applied to invoices. 0 for the common case (SA school fees are largely VAT-exempt); set only where the school makes taxable supplies and is VAT-registered.';
comment on column public.schools.banking_details is 'Free-text bank account details printed on invoices for EFT payers (account name / number / branch / reference guidance).';

-- ---------------------------------------------------------------------------
-- 1. fee_document_counters — gap-free per-school sequence for invoice /
-- receipt numbers. Not RLS-exposed at all (enable + force, zero policies):
-- only next_fee_document_number() ever touches it.

create table public.fee_document_counters (
  school_id   uuid not null references public.schools (id) on delete cascade,
  doc_type    text not null check (doc_type in ('invoice', 'receipt')),
  next_value  bigint not null default 1 check (next_value >= 1),
  primary key (school_id, doc_type)
);

comment on table public.fee_document_counters is 'Monotonic per-school, per-type counter behind next_fee_document_number(). Never written directly by a client (no RLS policy); the row is upserted and incremented under a row lock inside that SECURITY DEFINER function.';

alter table public.fee_document_counters enable row level security;
alter table public.fee_document_counters force row level security;

create or replace function public.next_fee_document_number(p_school_id uuid, p_doc_type text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next   bigint;
  v_prefix text;
  v_year   text := to_char(now() at time zone 'Africa/Johannesburg', 'YYYY');
begin
  if p_doc_type not in ('invoice', 'receipt') then
    raise exception 'invalid_argument: doc_type must be invoice or receipt';
  end if;

  insert into public.fee_document_counters (school_id, doc_type, next_value)
  values (p_school_id, p_doc_type, 1)
  on conflict (school_id, doc_type) do nothing;

  update public.fee_document_counters
    set next_value = next_value + 1
    where school_id = p_school_id and doc_type = p_doc_type
    returning next_value - 1 into v_next;

  select case when p_doc_type = 'invoice' then invoice_number_prefix else receipt_number_prefix end
    into v_prefix
    from public.schools
    where id = p_school_id;

  return coalesce(v_prefix, upper(substr(p_doc_type, 1, 3))) || '-' || v_year || '-' || lpad(v_next::text, 5, '0');
end;
$$;

comment on function public.next_fee_document_number(uuid, text) is
  'Returns the next gap-free document number for a school (e.g. INV-2026-00042). Internal — called only from other SECURITY DEFINER fee functions'' bodies, never granted to authenticated.';

revoke execute on function public.next_fee_document_number(uuid, text) from public;

-- ---------------------------------------------------------------------------
-- 2. invoices — a numbered, dated grouping of charges.

create type public.invoice_status as enum ('draft', 'issued', 'void');

create table public.invoices (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools (id) on delete cascade,
  learner_id       uuid not null references public.learners (id) on delete cascade,
  academic_year_id uuid not null references public.academic_years (id),
  invoice_number   text,
  status           public.invoice_status not null default 'draft',
  issue_date       date,
  due_date         date,
  notes            text,
  vat_rate         numeric(5, 2) not null default 0 check (vat_rate >= 0 and vat_rate <= 100),
  subtotal         numeric(12, 2) not null default 0 check (subtotal >= 0),
  vat_amount       numeric(12, 2) not null default 0 check (vat_amount >= 0),
  total            numeric(12, 2) not null default 0 check (total >= 0),
  issued_at        timestamptz,
  issued_by        uuid references public.profiles (id) on delete set null,
  voided_at        timestamptz,
  voided_by        uuid references public.profiles (id) on delete set null,
  void_reason      text,
  created_by       uuid references public.profiles (id) on delete set null,
  updated_by       uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint invoices_issued_has_number check (status <> 'issued' or invoice_number is not null),
  constraint invoices_void_has_reason check (status <> 'void' or void_reason is not null)
);

comment on table public.invoices is 'A numbered, dated, lockable grouping of learner_fee_charges. subtotal/vat_amount/total are snapshotted at issue time for historical integrity and PDF rendering; while draft they track sum(linked active charges). status/invoice_number/snapshot columns are only ever changed by issue_fee_invoice() / void_fee_invoice() — a direct client write to them is blocked by invoices_protect_lifecycle().';
comment on column public.invoices.invoice_number is 'NULL while draft; assigned a gap-free per-school number (schools.invoice_number_prefix) by issue_fee_invoice(). Unique per school.';

create unique index invoices_school_number_key on public.invoices (school_id, invoice_number) where invoice_number is not null;
create index invoices_school_id_idx on public.invoices (school_id);
create index invoices_learner_id_idx on public.invoices (learner_id);
create index invoices_academic_year_id_idx on public.invoices (academic_year_id);
create index invoices_status_idx on public.invoices (school_id, status);
create index invoices_due_date_idx on public.invoices (due_date) where status = 'issued';

create trigger invoices_set_updated_at
  before update on public.invoices
  for each row execute function public.set_updated_at();

create trigger invoices_set_created_updated_by
  before insert or update on public.invoices
  for each row execute function public.set_created_updated_by();

create or replace function public.invoices_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger invoices_validate_tenant_trigger
  before insert or update on public.invoices
  for each row execute function public.invoices_validate_tenant();

-- status / number / snapshot / lifecycle-timestamp columns are RPC-only.
-- A plain client UPDATE may still edit notes / due_date / issue_date while
-- the invoice is a draft (see invoices_update policy) — that is the
-- low-risk editing surface, mirroring bank_statement_lines' 'ignored'
-- carve-out.
create or replace function public.invoices_protect_lifecycle()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('app.allow_invoice_write', true), '') = 'true' then
    return new;
  end if;

  if tg_op = 'UPDATE' and (
       new.status is distinct from old.status
    or new.invoice_number is distinct from old.invoice_number
    or new.subtotal is distinct from old.subtotal
    or new.vat_amount is distinct from old.vat_amount
    or new.total is distinct from old.total
    or new.vat_rate is distinct from old.vat_rate
    or new.issued_at is distinct from old.issued_at
    or new.issued_by is distinct from old.issued_by
    or new.voided_at is distinct from old.voided_at
    or new.voided_by is distinct from old.voided_by
    or new.void_reason is distinct from old.void_reason
  ) then
    raise exception 'insufficient_privilege: invoice status/number/totals can only be changed by issue_fee_invoice() / void_fee_invoice()';
  end if;

  if tg_op = 'UPDATE' and old.status <> 'draft'
     and (new.notes is distinct from old.notes or new.due_date is distinct from old.due_date or new.issue_date is distinct from old.issue_date) then
    raise exception 'invoice_locked: an issued or void invoice cannot be edited';
  end if;

  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception 'insufficient_privilege: an invoice must be created as a draft';
  end if;

  return new;
end;
$$;

create trigger invoices_protect_lifecycle_trigger
  before insert or update on public.invoices
  for each row execute function public.invoices_protect_lifecycle();

-- ---------------------------------------------------------------------------
-- 3. Link charges to invoices. A charge may belong to at most one invoice;
-- a charge on an issued/void invoice is frozen (invoice line-items are
-- part of the snapshot).

alter table public.learner_fee_charges
  add column if not exists invoice_id uuid references public.invoices (id) on delete set null;

comment on column public.learner_fee_charges.invoice_id is 'The invoice this charge is a line item of, if any. A charge attached to a non-draft invoice cannot be edited or voided directly (learner_fee_charges_guard_invoice_lock) — void the invoice instead.';

create index learner_fee_charges_invoice_id_idx on public.learner_fee_charges (invoice_id);

create or replace function public.learner_fee_charges_guard_invoice_lock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.invoice_status;
  v_invoice_school uuid;
  v_invoice_learner uuid;
begin
  if coalesce(current_setting('app.allow_invoice_write', true), '') = 'true' then
    return new;
  end if;

  -- Block edits to a charge frozen onto a non-draft invoice.
  if tg_op = 'UPDATE' and old.invoice_id is not null then
    select status into v_status from public.invoices where id = old.invoice_id;
    if v_status is distinct from 'draft' then
      raise exception 'invoice_locked: this charge is part of invoice % and cannot be changed directly', old.invoice_id;
    end if;
  end if;

  -- Validate any invoice_id a client sets: same school + same learner, draft only.
  if new.invoice_id is not null and (tg_op = 'INSERT' or new.invoice_id is distinct from old.invoice_id) then
    select school_id, learner_id, status into v_invoice_school, v_invoice_learner, v_status
      from public.invoices where id = new.invoice_id;
    if v_invoice_school is distinct from new.school_id then
      raise exception 'insufficient_privilege: invoice_id must belong to the same school';
    end if;
    if v_invoice_learner is distinct from new.learner_id then
      raise exception 'insufficient_privilege: invoice_id must belong to the same learner';
    end if;
    if v_status is distinct from 'draft' then
      raise exception 'invoice_locked: cannot add a charge to an issued or void invoice';
    end if;
  end if;

  return new;
end;
$$;

create trigger learner_fee_charges_guard_invoice_lock_trigger
  before insert or update on public.learner_fee_charges
  for each row execute function public.learner_fee_charges_guard_invoice_lock();

-- ---------------------------------------------------------------------------
-- 4. learner_fee_payment_allocations — attribute part of a payment to an
-- invoice. RPC-only (allocate_fee_payment): the sum invariants below can
-- race under concurrent client writes.

create table public.learner_fee_payment_allocations (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references public.schools (id) on delete cascade,
  payment_id  uuid not null references public.learner_fee_payments (id) on delete cascade,
  invoice_id  uuid not null references public.invoices (id) on delete cascade,
  amount      numeric(12, 2) not null check (amount > 0),
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (payment_id, invoice_id)
);

comment on table public.learner_fee_payment_allocations is 'Attributes a portion of one payment to one invoice. sum(amount) per payment never exceeds that payment''s amount; sum(amount) per invoice never exceeds that invoice''s total — both enforced in allocate_fee_payment(), the only permitted writer. Unallocated payment amount is an account-level credit (unchanged behaviour).';

create index learner_fee_payment_allocations_school_id_idx on public.learner_fee_payment_allocations (school_id);
create index learner_fee_payment_allocations_payment_id_idx on public.learner_fee_payment_allocations (payment_id);
create index learner_fee_payment_allocations_invoice_id_idx on public.learner_fee_payment_allocations (invoice_id);

-- ---------------------------------------------------------------------------
-- 5. fee_receipts — a numbered acknowledgement of one payment.

create table public.fee_receipts (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null references public.schools (id) on delete cascade,
  learner_id      uuid not null references public.learners (id) on delete cascade,
  payment_id      uuid not null references public.learner_fee_payments (id) on delete cascade,
  receipt_number  text not null,
  issued_at       timestamptz not null default now(),
  issued_by       uuid references public.profiles (id) on delete set null,
  unique (payment_id),
  unique (school_id, receipt_number)
);

comment on table public.fee_receipts is 'One row per payment that has had a receipt issued. issue_fee_receipt() is idempotent — a payment already receipted returns its existing row. Never updated or deleted (no policy) — a receipt is a permanent acknowledgement.';

create index fee_receipts_school_id_idx on public.fee_receipts (school_id);
create index fee_receipts_learner_id_idx on public.fee_receipts (learner_id);

-- ---------------------------------------------------------------------------
-- 6. RLS — same actor set as the rest of the fees domain, plus guardian
-- SELECT on their own child's rows.

alter table public.invoices enable row level security;
alter table public.invoices force row level security;
alter table public.learner_fee_payment_allocations enable row level security;
alter table public.learner_fee_payment_allocations force row level security;
alter table public.fee_receipts enable row level security;
alter table public.fee_receipts force row level security;

create policy invoices_select on public.invoices
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy invoices_select_for_guardians on public.invoices
  for select to authenticated using (public.is_learner_guardian(learner_id) and status <> 'draft');
create policy invoices_insert on public.invoices
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy invoices_update on public.invoices
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));
-- No DELETE policy — void, never delete.

create policy learner_fee_payment_allocations_select on public.learner_fee_payment_allocations
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy learner_fee_payment_allocations_select_for_guardians on public.learner_fee_payment_allocations
  for select to authenticated using (
    exists (select 1 from public.invoices i where i.id = invoice_id and public.is_learner_guardian(i.learner_id))
  );
-- No INSERT/UPDATE/DELETE policy — allocate_fee_payment() only.

create policy fee_receipts_select on public.fee_receipts
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy fee_receipts_select_for_guardians on public.fee_receipts
  for select to authenticated using (public.is_learner_guardian(learner_id));
-- No INSERT/UPDATE/DELETE policy — issue_fee_receipt() only.

comment on policy invoices_select_for_guardians on public.invoices is
  'A guardian sees their own linked child''s invoices, but only once issued — a draft invoice is internal finance-office working state.';

-- ---------------------------------------------------------------------------
-- 7. Lifecycle RPCs.

-- issue_fee_invoice — draft -> issued. Assigns a number, snapshots totals,
-- sets issue/due dates, notifies the learner's guardians.
create or replace function public.issue_fee_invoice(
  p_invoice_id uuid,
  p_issue_date date default null,
  p_due_date   date default null
) returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_subtotal numeric(12, 2);
  v_charge_count int;
  v_vat_rate numeric(5, 2);
  v_vat_amount numeric(12, 2);
  v_number text;
  v_issue_date date;
  v_due_date date;
  v_due_days int;
  v_result public.invoices;
  v_learner record;
  v_guardian record;
begin
  select * into v_invoice from public.invoices where id = p_invoice_id;
  if not found then
    raise exception 'not_found: no invoice %', p_invoice_id;
  end if;
  if not public.can_manage_learner_financial(v_invoice.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'invalid_state: only a draft invoice can be issued';
  end if;

  select coalesce(sum(amount), 0), count(*)
    into v_subtotal, v_charge_count
    from public.learner_fee_charges
    where invoice_id = p_invoice_id and active;

  if v_charge_count = 0 then
    raise exception 'invalid_state: cannot issue an invoice with no line items';
  end if;

  select coalesce(vat_rate, 0), coalesce(invoice_due_days, 30)
    into v_vat_rate, v_due_days
    from public.schools where id = v_invoice.school_id;

  v_issue_date := coalesce(p_issue_date, current_date);
  v_due_date := coalesce(p_due_date, v_issue_date + v_due_days);
  v_vat_amount := round(v_subtotal * v_vat_rate / 100, 2);
  v_number := public.next_fee_document_number(v_invoice.school_id, 'invoice');

  perform set_config('app.allow_invoice_write', 'true', true);
  update public.invoices set
    status = 'issued',
    invoice_number = v_number,
    issue_date = v_issue_date,
    due_date = v_due_date,
    vat_rate = v_vat_rate,
    subtotal = v_subtotal,
    vat_amount = v_vat_amount,
    total = v_subtotal + v_vat_amount,
    issued_at = now(),
    issued_by = auth.uid()
  where id = p_invoice_id
  returning * into v_result;
  perform set_config('app.allow_invoice_write', 'false', true);

  perform public.write_audit_log(
    v_invoice.school_id, auth.uid(), 'invoice_issued', 'invoices', p_invoice_id,
    null, jsonb_build_object('invoice_number', v_number, 'total', v_result.total, 'due_date', v_due_date)
  );

  -- Notify each guardian of the learner (in-app; email hand-off unchanged).
  select first_name, last_name into v_learner from public.learners where id = v_invoice.learner_id;
  for v_guardian in
    select guardian_profile_id from public.learner_guardians where learner_id = v_invoice.learner_id
  loop
    perform public.create_notification(
      v_guardian.guardian_profile_id,
      'invoice_issued',
      'New invoice ' || v_number,
      'Invoice ' || v_number || ' for ' || coalesce(v_learner.first_name, '') || ' ' || coalesce(v_learner.last_name, '')
        || ' — R' || to_char(v_result.total, 'FM999999990.00') || ' due ' || to_char(v_due_date, 'DD Mon YYYY') || '.',
      v_invoice.school_id, 'invoices', p_invoice_id, '/parent/fees'
    );
  end loop;

  return v_result;
end;
$$;

comment on function public.issue_fee_invoice(uuid, date, date) is
  'Transitions a draft invoice to issued: assigns a gap-free number, snapshots subtotal/VAT/total from its active charges, sets issue/due dates, writes an audit row, and raises an in-app notification for each of the learner''s guardians.';

revoke execute on function public.issue_fee_invoice(uuid, date, date) from public;
grant execute on function public.issue_fee_invoice(uuid, date, date) to authenticated;

-- void_fee_invoice — issued|draft -> void. Deactivates the linked charges
-- so they leave the derived balance, and removes any allocations to it.
create or replace function public.void_fee_invoice(p_invoice_id uuid, p_reason text)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.invoices;
  v_result public.invoices;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'invalid_argument: a void reason is required';
  end if;

  select * into v_invoice from public.invoices where id = p_invoice_id;
  if not found then
    raise exception 'not_found: no invoice %', p_invoice_id;
  end if;
  if not public.can_manage_learner_financial(v_invoice.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;
  if v_invoice.status = 'void' then
    raise exception 'invalid_state: invoice is already void';
  end if;

  perform set_config('app.allow_invoice_write', 'true', true);
  update public.learner_fee_charges set active = false where invoice_id = p_invoice_id and active;
  delete from public.learner_fee_payment_allocations where invoice_id = p_invoice_id;
  update public.invoices set
    status = 'void',
    voided_at = now(),
    voided_by = auth.uid(),
    void_reason = p_reason
  where id = p_invoice_id
  returning * into v_result;
  perform set_config('app.allow_invoice_write', 'false', true);

  perform public.write_audit_log(
    v_invoice.school_id, auth.uid(), 'invoice_voided', 'invoices', p_invoice_id,
    jsonb_build_object('invoice_number', v_invoice.invoice_number, 'total', v_invoice.total),
    jsonb_build_object('void_reason', p_reason)
  );

  return v_result;
end;
$$;

comment on function public.void_fee_invoice(uuid, text) is
  'Voids an invoice (draft or issued): deactivates its line-item charges so they leave the derived balance, removes any payment allocations to it, and records the reason. The invoice row and number are retained permanently.';

revoke execute on function public.void_fee_invoice(uuid, text) from public;
grant execute on function public.void_fee_invoice(uuid, text) to authenticated;

-- allocate_fee_payment — replace the full allocation set for one payment.
create or replace function public.allocate_fee_payment(p_payment_id uuid, p_allocations jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.learner_fee_payments;
  v_alloc jsonb;
  v_invoice_id uuid;
  v_amount numeric(12, 2);
  v_total_alloc numeric(12, 2) := 0;
  v_invoice record;
  v_already numeric(12, 2);
begin
  select * into v_payment from public.learner_fee_payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: no payment %', p_payment_id;
  end if;
  if not public.can_manage_learner_financial(v_payment.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;
  if jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'invalid_argument: allocations must be a JSON array of {invoice_id, amount}';
  end if;

  delete from public.learner_fee_payment_allocations where payment_id = p_payment_id;

  for v_alloc in select * from jsonb_array_elements(p_allocations)
  loop
    v_invoice_id := (v_alloc ->> 'invoice_id')::uuid;
    v_amount := round((v_alloc ->> 'amount')::numeric, 2);
    if v_amount <= 0 then
      raise exception 'invalid_argument: allocation amount must be positive';
    end if;

    select id, school_id, learner_id, total into v_invoice
      from public.invoices where id = v_invoice_id;
    if not found then
      raise exception 'not_found: no invoice %', v_invoice_id;
    end if;
    if v_invoice.school_id is distinct from v_payment.school_id then
      raise exception 'insufficient_privilege: invoice must belong to the same school as the payment';
    end if;
    if v_invoice.learner_id is distinct from v_payment.learner_id then
      raise exception 'insufficient_privilege: invoice must belong to the same learner as the payment';
    end if;

    select coalesce(sum(amount), 0) into v_already
      from public.learner_fee_payment_allocations
      where invoice_id = v_invoice_id and payment_id <> p_payment_id;
    if v_already + v_amount > v_invoice.total then
      raise exception 'invalid_argument: allocations to invoice % (% + %) exceed its total %', v_invoice_id, v_already, v_amount, v_invoice.total;
    end if;

    insert into public.learner_fee_payment_allocations (school_id, payment_id, invoice_id, amount, created_by)
    values (v_payment.school_id, p_payment_id, v_invoice_id, v_amount, auth.uid());

    v_total_alloc := v_total_alloc + v_amount;
  end loop;

  if v_total_alloc > v_payment.amount then
    raise exception 'invalid_argument: total allocations % exceed the payment amount %', v_total_alloc, v_payment.amount;
  end if;

  perform public.write_audit_log(
    v_payment.school_id, auth.uid(), 'payment_allocated', 'learner_fee_payments', p_payment_id,
    null, jsonb_build_object('allocations', p_allocations, 'total_allocated', v_total_alloc)
  );
end;
$$;

comment on function public.allocate_fee_payment(uuid, jsonb) is
  'Replaces the entire allocation set for one payment atomically. Enforces: each invoice same school + same learner as the payment; per-invoice allocations never exceed the invoice total; total allocations never exceed the payment amount. Pass [] to clear all allocations.';

revoke execute on function public.allocate_fee_payment(uuid, jsonb) from public;
grant execute on function public.allocate_fee_payment(uuid, jsonb) to authenticated;

-- issue_fee_receipt — idempotent receipt for a payment.
create or replace function public.issue_fee_receipt(p_payment_id uuid)
returns public.fee_receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.learner_fee_payments;
  v_existing public.fee_receipts;
  v_number text;
  v_result public.fee_receipts;
begin
  select * into v_payment from public.learner_fee_payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: no payment %', p_payment_id;
  end if;
  if not public.can_manage_learner_financial(v_payment.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;

  select * into v_existing from public.fee_receipts where payment_id = p_payment_id;
  if found then
    return v_existing;
  end if;

  v_number := public.next_fee_document_number(v_payment.school_id, 'receipt');

  insert into public.fee_receipts (school_id, learner_id, payment_id, receipt_number, issued_by)
  values (v_payment.school_id, v_payment.learner_id, p_payment_id, v_number, auth.uid())
  returning * into v_result;

  perform public.write_audit_log(
    v_payment.school_id, auth.uid(), 'receipt_issued', 'fee_receipts', v_result.id,
    null, jsonb_build_object('receipt_number', v_number, 'payment_id', p_payment_id, 'amount', v_payment.amount)
  );

  return v_result;
end;
$$;

comment on function public.issue_fee_receipt(uuid) is
  'Idempotently issues a numbered receipt for a payment. A payment that already has a receipt returns the existing row unchanged.';

revoke execute on function public.issue_fee_receipt(uuid) from public;
grant execute on function public.issue_fee_receipt(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Audit trail on invoices — a narrow trigger allowlist, exactly the
-- shape 20260829090000_audit_log.sql established for the two Finance
-- tables that had no RPC front door. Draft-invoice edits (notes, dates)
-- are plain client writes with no RPC, so they get the trigger; the
-- lifecycle RPCs above already write their own richer audit rows.

create trigger invoices_audit_log
  after insert or update on public.invoices
  for each row execute function public.audit_log_from_trigger();
