-- Fees / Financial Domain
--
-- Ledger model: charges (learner_fee_charges) and payments
-- (learner_fee_payments) are independent rows against a learner's account;
-- balance/status is derived by aggregation at query time, not stored. This
-- was chosen over a per-charge payment-allocation model because every
-- requested capability (total charged, paid, outstanding balance, status,
-- last payment, history, outstanding items) falls out of a simple sum —
-- allocation would be materially more complex with nothing in the brief
-- requiring it. A "payment plan" is just several charges with different
-- due_dates; no separate scheduling table is needed for that.
--
-- fee_structures is a reusable per-school catalogue (e.g. "Term 1 Tuition —
-- Grade 1"), optionally referenced by a charge — but this migration does
-- not require the application to use it; ad-hoc per-learner charges
-- (fee_structure_id null) are equally valid, matching learner_documents'
-- own "the mechanism doesn't have to exist for the table to be useful"
-- precedent.
--
-- RBAC: finance_manager and accountant already existed as roles with zero
-- permissions beyond school.view — reserved, per rolePermissions.ts's own
-- shape, for exactly this domain. school_owner gets full manage; principal
-- gets view-only, the same duty-of-care-but-not-management exception
-- learner_medical_information already established for principal.
--
-- SECURITY DEFINER — applied precisely, per the assessments migration's own
-- documented lesson (Sprint 7 header comment), not reflexively:
--   - fee_structures_validate_tenant() reads academic_years and grades,
--     both gated by can_view_academic()/can_manage_academic() — which
--     finance_manager/accountant do NOT hold. Needs SECURITY DEFINER, or
--     every finance_manager-created fee structure fails silently.
--   - learner_fee_charges_validate_tenant() and
--     learner_fee_payments_validate_tenant() read `learners`, gated by
--     can_view_learners() — which finance_manager/accountant also do NOT
--     hold. Same reasoning, same fix: SECURITY DEFINER.
--   - can_view_learner_financial()/can_manage_learner_financial() only
--     check role + current_tenant_id() (itself SECURITY DEFINER) — no
--     other gated table read, so plain SECURITY INVOKER is correct,
--     exactly mirroring can_view_learner_medical()'s own shape.

create type public.fee_category as enum ('tuition', 'transport', 'boarding', 'uniform', 'activity', 'other');

create type public.fee_payment_method as enum ('cash', 'eft', 'card', 'debit_order', 'cheque', 'other');

-- ---------------------------------------------------------------------------
-- fee_structures — school's reusable fee catalogue.

create table public.fee_structures (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  grade_id          uuid references public.grades (id),
  name              text not null check (char_length(name) > 0),
  category          public.fee_category not null default 'other',
  amount            numeric(12, 2) not null check (amount > 0),
  description       text,
  active            boolean not null default true,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.fee_structures is 'Reusable per-school fee catalogue (e.g. "Term 1 Tuition — Grade 1"). Optional — learner_fee_charges may reference one or be entirely ad-hoc. Never hard-deleted — active=false is the archive state.';
comment on column public.fee_structures.grade_id is 'NULL = applies to any grade; set = scoped to one grade.';

create index fee_structures_school_id_idx on public.fee_structures (school_id);
create index fee_structures_academic_year_id_idx on public.fee_structures (academic_year_id);
create index fee_structures_grade_id_idx on public.fee_structures (grade_id);

create trigger fee_structures_set_updated_at
  before update on public.fee_structures
  for each row
  execute function public.set_updated_at();

create trigger fee_structures_set_created_updated_by
  before insert or update on public.fee_structures
  for each row
  execute function public.set_created_updated_by();

create or replace function public.fee_structures_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_school_id uuid;
  v_grade_school_id uuid;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  if new.grade_id is not null then
    select school_id into v_grade_school_id from public.grades where id = new.grade_id;
    if v_grade_school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: grade_id must belong to the same school';
    end if;
  end if;

  return new;
end;
$$;

create trigger fee_structures_validate_tenant_trigger
  before insert or update on public.fee_structures
  for each row
  execute function public.fee_structures_validate_tenant();

-- ---------------------------------------------------------------------------
-- learner_fee_charges — invoice line items charged to a learner.

create table public.learner_fee_charges (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools (id) on delete cascade,
  learner_id         uuid not null references public.learners (id) on delete cascade,
  academic_year_id   uuid not null references public.academic_years (id),
  fee_structure_id   uuid references public.fee_structures (id),
  description        text not null check (char_length(description) > 0),
  category           public.fee_category not null default 'other',
  amount             numeric(12, 2) not null check (amount > 0),
  due_date           date,
  notes              text,
  active             boolean not null default true,
  created_by         uuid references public.profiles (id) on delete set null,
  updated_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.learner_fee_charges is 'One row per charge/invoice line item raised against a learner. No stored status — outstanding balance and status are derived by aggregating against learner_fee_payments at query time. Never hard-deleted — active=false excludes a charge entered in error from the balance without destroying the record.';

create index learner_fee_charges_school_id_idx on public.learner_fee_charges (school_id);
create index learner_fee_charges_learner_id_idx on public.learner_fee_charges (learner_id);
create index learner_fee_charges_academic_year_id_idx on public.learner_fee_charges (academic_year_id);
create index learner_fee_charges_fee_structure_id_idx on public.learner_fee_charges (fee_structure_id);

create trigger learner_fee_charges_set_updated_at
  before update on public.learner_fee_charges
  for each row
  execute function public.set_updated_at();

create trigger learner_fee_charges_set_created_updated_by
  before insert or update on public.learner_fee_charges
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_fee_charges_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
  v_structure record;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  if new.fee_structure_id is not null then
    select school_id, academic_year_id into v_structure from public.fee_structures where id = new.fee_structure_id;
    if v_structure.school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: fee_structure_id must belong to the same school';
    end if;
    if v_structure.academic_year_id is distinct from new.academic_year_id then
      raise exception 'insufficient_privilege: fee_structure_id must belong to the same academic year';
    end if;
  end if;

  return new;
end;
$$;

create trigger learner_fee_charges_validate_tenant_trigger
  before insert or update on public.learner_fee_charges
  for each row
  execute function public.learner_fee_charges_validate_tenant();

-- ---------------------------------------------------------------------------
-- learner_fee_payments — payments received against a learner's account.

create table public.learner_fee_payments (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  learner_id        uuid not null references public.learners (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  amount            numeric(12, 2) not null check (amount > 0),
  payment_date      date not null,
  method            public.fee_payment_method not null default 'other',
  reference         text,
  notes             text,
  active            boolean not null default true,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.learner_fee_payments is 'One row per payment received from/on behalf of a learner. Never hard-deleted — active=false excludes a payment entered in error from the balance without destroying the record. A mismarked entry is corrected via UPDATE, same as every other table in this schema.';

create index learner_fee_payments_school_id_idx on public.learner_fee_payments (school_id);
create index learner_fee_payments_learner_id_idx on public.learner_fee_payments (learner_id);
create index learner_fee_payments_academic_year_id_idx on public.learner_fee_payments (academic_year_id);

create trigger learner_fee_payments_set_updated_at
  before update on public.learner_fee_payments
  for each row
  execute function public.set_updated_at();

create trigger learner_fee_payments_set_created_updated_by
  before insert or update on public.learner_fee_payments
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_fee_payments_validate_tenant()
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

create trigger learner_fee_payments_validate_tenant_trigger
  before insert or update on public.learner_fee_payments
  for each row
  execute function public.learner_fee_payments_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.fee_structures enable row level security;
alter table public.fee_structures force row level security;
alter table public.learner_fee_charges enable row level security;
alter table public.learner_fee_charges force row level security;
alter table public.learner_fee_payments enable row level security;
alter table public.learner_fee_payments force row level security;

-- Mirrors the app-level learner.view_financial permission — school_owner,
-- principal (duty-of-care exception, same shape as learner medical),
-- finance_manager, accountant, or any platform admin.
create or replace function public.can_view_learner_financial(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'finance_manager', 'accountant')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_learner_financial(uuid) is
  'Mirrors the app-level learner.view_financial permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- Mirrors the app-level learner.manage_financial permission — narrower than
-- view (principal can see fees but not edit them, same duty-of-care-but-
-- not-management shape as learner_medical_information).
create or replace function public.can_manage_learner_financial(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'finance_manager', 'accountant')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_learner_financial(uuid) is
  'Mirrors the app-level learner.manage_financial permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

grant execute on function public.can_view_learner_financial(uuid) to authenticated;
grant execute on function public.can_manage_learner_financial(uuid) to authenticated;

create policy fee_structures_select on public.fee_structures
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy fee_structures_insert on public.fee_structures
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy fee_structures_update on public.fee_structures
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));

create policy learner_fee_charges_select on public.learner_fee_charges
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy learner_fee_charges_insert on public.learner_fee_charges
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy learner_fee_charges_update on public.learner_fee_charges
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));

create policy learner_fee_payments_select on public.learner_fee_payments
  for select to authenticated using (public.can_view_learner_financial(school_id));
create policy learner_fee_payments_insert on public.learner_fee_payments
  for insert to authenticated with check (public.can_manage_learner_financial(school_id));
create policy learner_fee_payments_update on public.learner_fee_payments
  for update to authenticated using (public.can_manage_learner_financial(school_id)) with check (public.can_manage_learner_financial(school_id));

-- No DELETE policy on any of the three tables — combined with FORCE ROW
-- LEVEL SECURITY, hard delete is impossible for any authenticated caller,
-- same as every other table in this schema.
