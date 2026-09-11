-- Fees Domain Extension — Adjustments (discounts/bursaries/scholarships/
-- waivers) and Refunds
--
-- Additive only. The existing charges/payments ledger model
-- (20260823120000_fees_domain.sql: "balance is derived by aggregation at
-- query time, not stored") is not broken and is not touched — this
-- migration extends the SAME ledger pattern with two more row types that
-- aggregate into the same derived balance, rather than replacing it with an
-- allocation/invoice model. That existing design decision is preserved
-- deliberately, per the standing instruction not to rebuild working
-- functionality without evidence of failure.
--
-- RBAC: reuses can_view_learner_financial()/can_manage_learner_financial()
-- verbatim — the actor set for "who may see/adjust a learner's fee
-- position" does not change just because a new row type was added to that
-- position. No new permission function, no new role.
--
-- SECURITY DEFINER — applied for the same reason documented in
-- 20260823120000_fees_domain.sql: both trigger functions below read
-- `learners` (gated by can_view_learners(), which finance_manager/
-- accountant do not hold), so they need SECURITY DEFINER or every
-- finance-role write fails silently against RLS on the referenced table.

create type public.fee_adjustment_type as enum ('discount', 'bursary', 'scholarship', 'waiver');

create type public.fee_adjustment_method as enum ('percentage', 'fixed_amount');

create type public.fee_refund_status as enum ('pending', 'completed', 'rejected');

-- ---------------------------------------------------------------------------
-- learner_fee_adjustments — a discount/bursary/scholarship/waiver reduces a
-- learner's outstanding balance. Optionally scoped to one charge (e.g. "10%
-- off this term's tuition"); null charge_id = a general account-level
-- adjustment (e.g. a sibling discount not tied to any single line item).
-- `amount` is always the resolved rand value removed from the balance —
-- `percentage` is retained only as an audit/display record of how that
-- amount was derived when method='percentage', never re-derived at read
-- time (matches assessments' own "never a nullable column meaning two
-- things" discipline: amount is always the authoritative number).

create table public.learner_fee_adjustments (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools (id) on delete cascade,
  learner_id         uuid not null references public.learners (id) on delete cascade,
  academic_year_id   uuid not null references public.academic_years (id),
  charge_id          uuid references public.learner_fee_charges (id),
  adjustment_type    public.fee_adjustment_type not null default 'discount',
  method             public.fee_adjustment_method not null default 'fixed_amount',
  percentage         numeric(5, 2),
  amount             numeric(12, 2) not null check (amount > 0),
  reason             text not null check (char_length(reason) > 0),
  active             boolean not null default true,
  created_by         uuid references public.profiles (id) on delete set null,
  updated_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint learner_fee_adjustments_percentage_range check (percentage is null or (percentage > 0 and percentage <= 100)),
  constraint learner_fee_adjustments_percentage_requires_method check (percentage is null or method = 'percentage')
);

comment on table public.learner_fee_adjustments is 'A discount/bursary/scholarship/waiver that reduces a learner''s derived fee balance — same ledger-aggregation model as learner_fee_charges/learner_fee_payments, not a mutation of the charge itself. Never hard-deleted — active=false is the archive state (e.g. an adjustment entered in error).';
comment on column public.learner_fee_adjustments.charge_id is 'NULL = a general account-level adjustment; set = scoped to one specific charge. Must belong to the same learner (learner_fee_adjustments_validate_tenant).';
comment on column public.learner_fee_adjustments.amount is 'The authoritative rand value removed from the balance. Always populated, including when method=percentage — percentage is retained for audit/display only, never re-derived at read time.';

create index learner_fee_adjustments_school_id_idx on public.learner_fee_adjustments (school_id);
create index learner_fee_adjustments_learner_id_idx on public.learner_fee_adjustments (learner_id);
create index learner_fee_adjustments_academic_year_id_idx on public.learner_fee_adjustments (academic_year_id);
create index learner_fee_adjustments_charge_id_idx on public.learner_fee_adjustments (charge_id);

create trigger learner_fee_adjustments_set_updated_at
  before update on public.learner_fee_adjustments
  for each row
  execute function public.set_updated_at();

create trigger learner_fee_adjustments_set_created_updated_by
  before insert or update on public.learner_fee_adjustments
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_fee_adjustments_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
  v_charge record;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  if new.charge_id is not null then
    select school_id, learner_id into v_charge from public.learner_fee_charges where id = new.charge_id;
    if v_charge.school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: charge_id must belong to the same school';
    end if;
    if v_charge.learner_id is distinct from new.learner_id then
      raise exception 'insufficient_privilege: charge_id must belong to the same learner';
    end if;
  end if;

  return new;
end;
$$;

create trigger learner_fee_adjustments_validate_tenant_trigger
  before insert or update on public.learner_fee_adjustments
  for each row
  execute function public.learner_fee_adjustments_validate_tenant();

-- ---------------------------------------------------------------------------
-- learner_fee_refunds — a refund against a specific prior payment. Only a
-- 'completed' refund reduces the derived net-paid figure (a 'pending'
-- request must not silently reduce a family's recorded payment history
-- before anyone has actually returned the money); 'rejected' never does.

create table public.learner_fee_refunds (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  learner_id        uuid not null references public.learners (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  payment_id        uuid not null references public.learner_fee_payments (id),
  amount            numeric(12, 2) not null check (amount > 0),
  refund_date       date not null,
  method            public.fee_payment_method not null default 'other',
  reference         text,
  reason            text not null check (char_length(reason) > 0),
  status            public.fee_refund_status not null default 'pending',
  active            boolean not null default true,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.learner_fee_refunds is 'A refund against one prior learner_fee_payments row. Only status=completed rows count against the derived balance/net-paid figure — pending/rejected refunds have no financial effect yet. Never hard-deleted — active=false is the archive state (e.g. a refund entered in error, distinct from status=rejected which means a real refund request was declined).';
comment on column public.learner_fee_refunds.amount is 'Enforced by learner_fee_refunds_validate_tenant() to never exceed the payment''s remaining refundable balance (payment amount minus already active completed/pending refunds against it).';

create index learner_fee_refunds_school_id_idx on public.learner_fee_refunds (school_id);
create index learner_fee_refunds_learner_id_idx on public.learner_fee_refunds (learner_id);
create index learner_fee_refunds_academic_year_id_idx on public.learner_fee_refunds (academic_year_id);
create index learner_fee_refunds_payment_id_idx on public.learner_fee_refunds (payment_id);

create trigger learner_fee_refunds_set_updated_at
  before update on public.learner_fee_refunds
  for each row
  execute function public.set_updated_at();

create trigger learner_fee_refunds_set_created_updated_by
  before insert or update on public.learner_fee_refunds
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_fee_refunds_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
  v_payment record;
  v_already_refunded numeric(12, 2);
  v_refundable numeric(12, 2);
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id, learner_id, amount into v_payment from public.learner_fee_payments where id = new.payment_id;
  if v_payment.school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: payment_id must belong to the same school';
  end if;
  if v_payment.learner_id is distinct from new.learner_id then
    raise exception 'insufficient_privilege: payment_id must belong to the same learner';
  end if;

  select coalesce(sum(amount), 0) into v_already_refunded
    from public.learner_fee_refunds
    where payment_id = new.payment_id
      and active
      and status in ('pending', 'completed')
      and id is distinct from new.id;

  v_refundable := v_payment.amount - v_already_refunded;
  if new.status in ('pending', 'completed') and new.amount > v_refundable then
    raise exception 'insufficient_privilege: refund amount % exceeds the refundable balance % for this payment', new.amount, v_refundable;
  end if;

  return new;
end;
$$;

create trigger learner_fee_refunds_validate_tenant_trigger
  before insert or update on public.learner_fee_refunds
  for each row
  execute function public.learner_fee_refunds_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS — identical actor set to the rest of the fees domain, reusing the
-- existing can_view_learner_financial()/can_manage_learner_financial()
-- helpers verbatim (20260823120000_fees_domain.sql).

alter table public.learner_fee_adjustments enable row level security;
alter table public.learner_fee_adjustments force row level security;
alter table public.learner_fee_refunds enable row level security;
alter table public.learner_fee_refunds force row level security;

create policy learner_fee_adjustments_select on public.learner_fee_adjustments
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy learner_fee_adjustments_insert on public.learner_fee_adjustments
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy learner_fee_adjustments_update on public.learner_fee_adjustments
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));

create policy learner_fee_refunds_select on public.learner_fee_refunds
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy learner_fee_refunds_insert on public.learner_fee_refunds
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy learner_fee_refunds_update on public.learner_fee_refunds
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));

-- No DELETE policy on either table — combined with FORCE ROW LEVEL
-- SECURITY, hard delete is impossible for any authenticated caller, same as
-- every other table in this schema. active=false is the only archive path.

-- ---------------------------------------------------------------------------
-- Guardian (Parent Portal) visibility — mirrors
-- learner_fee_charges_select_for_guardians/learner_fee_payments_select_for_guardians
-- from 20260825090000_parent_portal_v1.sql exactly: a guardian may see their
-- own linked learner's adjustments and refunds (so "why do I owe less than
-- the sticker price" and "was my overpayment refunded" are answerable in
-- the Parent Portal), never anyone else's.

create policy learner_fee_adjustments_select_for_guardians on public.learner_fee_adjustments
  for select to authenticated using (public.is_learner_guardian(learner_id));

create policy learner_fee_refunds_select_for_guardians on public.learner_fee_refunds
  for select to authenticated using (public.is_learner_guardian(learner_id));
