-- Sebetsa Phase H — Leave & Absence, migration 4 of 6.
--
-- leave_balance_transactions is the source of truth (append-only ledger,
-- same shape/guarantee as audit_log: no UPDATE/DELETE policy at all, no
-- direct client INSERT either — only the RPCs in migration 6 write to it).
-- leave_balances is a maintained snapshot/read-model derived from the
-- ledger, never hand-edited (see approved architecture §9/§22/§27).

create table public.leave_balances (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.organizations (id) on delete cascade,
  employee_id    uuid not null references public.employees (id) on delete cascade,
  leave_type_id  uuid not null references public.leave_types (id) on delete cascade,
  period_year    integer not null check (period_year >= 2000 and period_year <= 2100),
  opening_balance numeric not null default 0,
  accrued        numeric not null default 0,
  used           numeric not null default 0,
  pending        numeric not null default 0,
  adjustment     numeric not null default 0,
  carried_over   numeric not null default 0,
  remaining      numeric generated always as
    (opening_balance + accrued + carried_over + adjustment - used) stored,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (tenant_id, employee_id, leave_type_id, period_year)
);

comment on table public.leave_balances is
  'Maintained snapshot of leave balance per employee/leave_type/period_year. NOT the source of truth — leave_balance_transactions is. Written only by approve_leave_request/reject_leave_request/revoke_leave_request/adjust_leave_balance/recompute_leave_balance (migration 6); no direct client INSERT/UPDATE.';

create index leave_balances_tenant_id_idx on public.leave_balances (tenant_id);
create index leave_balances_employee_id_leave_type_id_idx on public.leave_balances (employee_id, leave_type_id);

create trigger leave_balances_set_updated_at
  before update on public.leave_balances
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_leave_balance_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.leave_types where id = new.leave_type_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: leave type % does not belong to tenant %', new.leave_type_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger leave_balances_validate_tenant_refs
  before insert or update on public.leave_balances
  for each row
  execute function public.validate_leave_balance_tenant_refs();

alter table public.leave_balances enable row level security;
alter table public.leave_balances force row level security;

-- No INSERT/UPDATE/DELETE policy for `authenticated` at all — every write
-- goes through a SECURITY DEFINER RPC (migration 6), same enforcement
-- shape as audit_log. SELECT only.
create policy leave_balances_select on public.leave_balances for select to authenticated
  using (
    public.can_view_leave_broad(tenant_id)
    or exists (select 1 from public.employees e where e.id = leave_balances.employee_id and e.profile_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- leave_balance_transactions: append-only ledger.

create table public.leave_balance_transactions (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  employee_id       uuid not null references public.employees (id) on delete cascade,
  leave_type_id     uuid not null references public.leave_types (id) on delete cascade,
  period_year       integer not null check (period_year >= 2000 and period_year <= 2100),
  transaction_type  text not null check (transaction_type in ('opening', 'accrual', 'usage', 'adjustment', 'carry_over', 'reversal')),
  amount            numeric not null,
  leave_request_id  uuid references public.leave_requests (id) on delete set null,
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);

comment on table public.leave_balance_transactions is
  'Append-only ledger — the authoritative source of truth for leave balances. No UPDATE/DELETE policy exists (impossible for any authenticated caller with FORCE ROW LEVEL SECURITY); no client INSERT policy either — every row is written by a SECURITY DEFINER RPC in migration 6.';

create index leave_balance_transactions_tenant_id_idx on public.leave_balance_transactions (tenant_id);
create index leave_balance_transactions_employee_leave_type_period_idx on public.leave_balance_transactions (employee_id, leave_type_id, period_year);
create index leave_balance_transactions_leave_request_id_idx on public.leave_balance_transactions (leave_request_id);

create or replace function public.validate_leave_balance_transaction_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.leave_types where id = new.leave_type_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: leave type % does not belong to tenant %', new.leave_type_id, new.tenant_id;
  end if;

  if new.leave_request_id is not null and not exists (
    select 1 from public.leave_requests where id = new.leave_request_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: leave request % does not belong to tenant %', new.leave_request_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger leave_balance_transactions_validate_tenant_refs
  before insert on public.leave_balance_transactions
  for each row
  execute function public.validate_leave_balance_transaction_tenant_refs();

alter table public.leave_balance_transactions enable row level security;
alter table public.leave_balance_transactions force row level security;

-- SELECT only — no INSERT/UPDATE/DELETE policy for `authenticated` at all.
create policy leave_balance_transactions_select on public.leave_balance_transactions for select to authenticated
  using (
    public.can_manage_leave(tenant_id)
    or exists (select 1 from public.employees e where e.id = leave_balance_transactions.employee_id and e.profile_id = auth.uid())
  );
