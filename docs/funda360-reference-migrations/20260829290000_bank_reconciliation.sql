-- FND-PAY-002: Bank reconciliation (statement import/match against
-- existing manual EFT/cash payments) — corrected in this Kanban to NOT
-- require FND-PAY-001 (the live payment gateway): this reconciles
-- payment records that already exist today (learner_fee_payments, manually
-- recorded EFT/cash entries), nothing to do with whether a live gateway
-- exists.
--
-- SCOPE: a finance user uploads a bank statement CSV; each line is parsed
-- client-side (reusing the existing generic parseCsv, same as learner CSV
-- import) and matched — deliberately NOT auto-committed — against
-- unreconciled learner_fee_payments rows at the same school by amount.
-- Auto-matching by amount+date alone is not trustworthy enough to write
-- silently (two learners could plausibly pay the identical amount on the
-- same day) — the finance user always explicitly confirms which payment a
-- statement line matches, or marks it "ignored" (bank charges, unrelated
-- transactions). This mirrors this schema's existing "server is the
-- source of truth for a derived state, but a human confirms the specific
-- transition" pattern.
--
-- CONSISTENCY: matching/unmatching a line always also flips the linked
-- learner_fee_payments.reconciled_at, and always does so together,
-- atomically, via reconcile_bank_statement_line()/
-- unreconcile_bank_statement_line() — never via two separate client
-- writes that could race or partially fail. Direct client UPDATEs to
-- either side of that link are blocked by trigger (see the two
-- protect_* functions below) — mirrors academic_years'
-- prevent_direct_year_activation()'s exact "only a specific function may
-- make this transition" precedent. A plain client UPDATE to
-- bank_statement_lines.status is still allowed for the low-risk
-- 'ignored' transition, which never touches learner_fee_payments at all.
--
-- ACCESS: same tier as learner_fee_payments itself
-- (can_view_learner_financial / can_manage_learner_financial) —
-- deliberately NO guardian access at all (unlike learner_fee_payments,
-- which guardians can see their own child's rows of): a bank statement is
-- an internal finance-office document covering every family's payments
-- at once, not a per-learner record a guardian has any reason to see.

create type public.bank_statement_line_status as enum ('unmatched', 'matched', 'ignored');

create table public.bank_reconciliation_imports (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  file_name    text not null,
  imported_at  timestamptz not null default now(),
  created_by   uuid references public.profiles (id) on delete set null
);

comment on table public.bank_reconciliation_imports is 'One row per uploaded bank statement CSV — an audit record of what was uploaded and by whom, not a data table itself (see bank_statement_lines for the parsed rows).';

create index bank_reconciliation_imports_school_id_idx on public.bank_reconciliation_imports (school_id);

create table public.bank_statement_lines (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools (id) on delete cascade,
  import_id          uuid not null references public.bank_reconciliation_imports (id) on delete cascade,
  transaction_date   date not null,
  description        text not null,
  amount             numeric(12,2) not null check (amount > 0),
  status             public.bank_statement_line_status not null default 'unmatched',
  matched_payment_id uuid references public.learner_fee_payments (id) on delete set null,
  matched_at         timestamptz,
  matched_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.bank_statement_lines is 'One row per parsed bank-statement CSV line. status=matched + matched_payment_id are only ever set together, in lockstep with the matched learner_fee_payments.reconciled_at, via reconcile_bank_statement_line() — never a direct client write (see bank_statement_lines_protect_match_fields trigger). status=ignored (e.g. bank charges, unrelated transactions) IS a plain client UPDATE — it never touches learner_fee_payments.';

create index bank_statement_lines_school_id_idx on public.bank_statement_lines (school_id);
create index bank_statement_lines_import_id_idx on public.bank_statement_lines (import_id);
create index bank_statement_lines_matched_payment_id_idx on public.bank_statement_lines (matched_payment_id);

create trigger bank_statement_lines_set_updated_at
  before update on public.bank_statement_lines
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- learner_fee_payments.reconciled_at — additive column, no new table for
-- this half (mirrors FND-WELL-004's "additive columns, not a new table"
-- precedent where the new state is genuinely a property of the existing
-- row, not a new entity).

alter table public.learner_fee_payments add column reconciled_at timestamptz;

comment on column public.learner_fee_payments.reconciled_at is 'Set only via reconcile_bank_statement_line() / cleared only via unreconcile_bank_statement_line() — see learner_fee_payments_protect_reconciled_at trigger. Null means "not yet matched against any bank statement line", not "definitely wrong" — most schools will have real payments that predate this feature or were never matched.';

create or replace function public.learner_fee_payments_protect_reconciled_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.reconciled_at is distinct from old.reconciled_at
     and coalesce(current_setting('app.allow_reconciliation_write', true), '') <> 'true' then
    raise exception 'insufficient_privilege: reconciled_at can only be changed by reconcile_bank_statement_line() / unreconcile_bank_statement_line()';
  end if;
  return new;
end;
$$;

create trigger learner_fee_payments_protect_reconciled_at_trigger
  before update on public.learner_fee_payments
  for each row
  execute function public.learner_fee_payments_protect_reconciled_at();

create or replace function public.bank_statement_lines_protect_match_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (new.status = 'matched' or new.matched_payment_id is not null or old.status = 'matched')
     and coalesce(current_setting('app.allow_reconciliation_write', true), '') <> 'true' then
    raise exception 'insufficient_privilege: matching/unmatching a statement line must go through reconcile_bank_statement_line() / unreconcile_bank_statement_line()';
  end if;
  return new;
end;
$$;

create trigger bank_statement_lines_protect_match_fields_trigger
  before update on public.bank_statement_lines
  for each row
  execute function public.bank_statement_lines_protect_match_fields();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.bank_reconciliation_imports enable row level security;
alter table public.bank_reconciliation_imports force row level security;
alter table public.bank_statement_lines enable row level security;
alter table public.bank_statement_lines force row level security;

-- Not set_created_updated_by() — that shared trigger unconditionally
-- writes both created_by AND updated_by, but this table is create-only
-- (no UPDATE policy, a genuinely immutable audit record), so it never
-- gained an updated_by column at all.
create or replace function public.bank_reconciliation_imports_set_created_by()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.created_by := auth.uid();
  return new;
end;
$$;

create trigger bank_reconciliation_imports_set_created_by_trigger
  before insert on public.bank_reconciliation_imports
  for each row
  execute function public.bank_reconciliation_imports_set_created_by();

create policy bank_reconciliation_imports_select on public.bank_reconciliation_imports
  for select to authenticated using (can_view_learner_financial(school_id));
create policy bank_reconciliation_imports_insert on public.bank_reconciliation_imports
  for insert to authenticated with check (can_manage_learner_financial(school_id));

create policy bank_statement_lines_select on public.bank_statement_lines
  for select to authenticated using (can_view_learner_financial(school_id));
create policy bank_statement_lines_insert on public.bank_statement_lines
  for insert to authenticated with check (can_manage_learner_financial(school_id) and status = 'unmatched');
create policy bank_statement_lines_update on public.bank_statement_lines
  for update to authenticated using (can_manage_learner_financial(school_id)) with check (can_manage_learner_financial(school_id));

-- No DELETE policy on either table — combined with FORCE ROW LEVEL
-- SECURITY, hard delete is impossible, same as every other table here.

-- ---------------------------------------------------------------------------
-- reconcile_bank_statement_line / unreconcile_bank_statement_line — the
-- only two functions allowed to touch the matched_* fields (see the two
-- protect_* triggers above).

create or replace function public.reconcile_bank_statement_line(p_line_id uuid, p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.bank_statement_lines;
  v_payment public.learner_fee_payments;
begin
  select * into v_line from public.bank_statement_lines where id = p_line_id;
  if not found then
    raise exception 'not_found: no bank statement line %', p_line_id;
  end if;
  if not public.can_manage_learner_financial(v_line.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;
  if v_line.status = 'matched' then
    raise exception 'already_matched: this statement line is already matched to a payment';
  end if;

  select * into v_payment from public.learner_fee_payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: no payment %', p_payment_id;
  end if;
  if v_payment.school_id is distinct from v_line.school_id then
    raise exception 'insufficient_privilege: the payment must belong to the same school as the statement line';
  end if;
  if v_payment.reconciled_at is not null then
    raise exception 'already_reconciled: this payment is already matched to another statement line';
  end if;

  perform set_config('app.allow_reconciliation_write', 'true', true);
  update public.bank_statement_lines
    set status = 'matched', matched_payment_id = p_payment_id, matched_at = now(), matched_by = auth.uid()
    where id = p_line_id;
  update public.learner_fee_payments set reconciled_at = now() where id = p_payment_id;
  perform set_config('app.allow_reconciliation_write', 'false', true);

  perform public.write_audit_log(
    v_line.school_id, auth.uid(), 'bank_statement_line_matched', 'bank_statement_lines', p_line_id,
    null, jsonb_build_object('payment_id', p_payment_id, 'amount', v_line.amount)
  );
end;
$$;

comment on function public.reconcile_bank_statement_line(uuid, uuid) is
  'Matches a bank statement line to a specific learner_fee_payments row and marks both accordingly, atomically. The only function permitted to do so — see bank_statement_lines_protect_match_fields / learner_fee_payments_protect_reconciled_at.';

revoke execute on function public.reconcile_bank_statement_line(uuid, uuid) from public;
grant execute on function public.reconcile_bank_statement_line(uuid, uuid) to authenticated;

create or replace function public.unreconcile_bank_statement_line(p_line_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.bank_statement_lines;
begin
  select * into v_line from public.bank_statement_lines where id = p_line_id;
  if not found then
    raise exception 'not_found: no bank statement line %', p_line_id;
  end if;
  if not public.can_manage_learner_financial(v_line.school_id) then
    raise exception 'insufficient_privilege: cannot manage financial records for this school';
  end if;
  if v_line.status <> 'matched' or v_line.matched_payment_id is null then
    raise exception 'not_matched: this statement line is not currently matched to a payment';
  end if;

  perform set_config('app.allow_reconciliation_write', 'true', true);
  update public.learner_fee_payments set reconciled_at = null where id = v_line.matched_payment_id;
  update public.bank_statement_lines set status = 'unmatched', matched_payment_id = null, matched_at = null, matched_by = null where id = p_line_id;
  perform set_config('app.allow_reconciliation_write', 'false', true);

  perform public.write_audit_log(
    v_line.school_id, auth.uid(), 'bank_statement_line_unmatched', 'bank_statement_lines', p_line_id,
    jsonb_build_object('payment_id', v_line.matched_payment_id), null
  );
end;
$$;

comment on function public.unreconcile_bank_statement_line(uuid) is
  'Undoes reconcile_bank_statement_line() — clears both sides of the match atomically. The only function permitted to do so.';

revoke execute on function public.unreconcile_bank_statement_line(uuid) from public;
grant execute on function public.unreconcile_bank_statement_line(uuid) to authenticated;
