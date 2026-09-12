-- Sebetsa Phase H — Leave & Absence, migration 3 of 6.
--
-- Extends the existing leave_requests table (created in
-- 20260911101000_scheduling_and_attendance.sql, hardened in
-- 20260911101700_scheduling_and_availability.sql) with the workflow columns
-- and lifecycle enforcement Phase H adds. Additive only — no historical
-- migration touched, no data dropped.
--
-- Existing-data safety: leave_type_id is added nullable, backfilled to each
-- tenant's seeded 'Other' leave type (seeded by the prior migration), then
-- promoted to NOT NULL only if the backfill left zero unmapped rows — if
-- hosted somehow has rows this can't cleanly map, the migration raises and
-- stops rather than silently forcing a bad default.

alter table public.leave_requests add column leave_type_id uuid references public.leave_types (id);
alter table public.leave_requests add column is_half_day boolean not null default false;
alter table public.leave_requests add column half_day_period text check (half_day_period is null or half_day_period in ('am', 'pm'));
alter table public.leave_requests add column supporting_document_ref text;
alter table public.leave_requests add column decision_notes text;
alter table public.leave_requests add column cancelled_at timestamptz;
alter table public.leave_requests add column cancelled_by uuid references public.profiles (id) on delete set null;

alter table public.leave_requests add constraint leave_requests_half_day_period_consistent check (
  (is_half_day = false and half_day_period is null)
  or (is_half_day = true and half_day_period is not null)
);

-- Backfill any pre-existing row to its tenant's 'Other' leave type.
do $$
declare
  v_unmapped int;
begin
  update public.leave_requests lr
  set leave_type_id = lt.id
  from public.leave_types lt
  where lr.leave_type_id is null
    and lt.tenant_id = lr.tenant_id
    and lt.name = 'Other';

  select count(*) into v_unmapped from public.leave_requests where leave_type_id is null;

  if v_unmapped > 0 then
    raise exception 'leave_requests_backfill_failed: % row(s) could not be mapped to a leave_type (tenant missing its seeded ''Other'' type) — resolve before promoting leave_type_id to NOT NULL', v_unmapped;
  end if;
end $$;

alter table public.leave_requests alter column leave_type_id set not null;

create index leave_requests_leave_type_id_idx on public.leave_requests (leave_type_id);
create index leave_requests_start_date_idx on public.leave_requests (start_date);
create index leave_requests_end_date_idx on public.leave_requests (end_date);

create or replace function public.validate_leave_request_leave_type_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.leave_types where id = new.leave_type_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: leave type % does not belong to tenant %', new.leave_type_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger leave_requests_validate_leave_type_tenant_ref
  before insert or update on public.leave_requests
  for each row
  execute function public.validate_leave_request_leave_type_tenant_ref();

-- ---------------------------------------------------------------------------
-- Lifecycle enforcement. Mirrors the Funda360 leave_management prior art
-- (docs/funda360-reference-migrations/20260829230000_leave_management.sql):
-- force every INSERT to 'pending' regardless of caller-supplied status, and
-- derive decided_by/decided_at/cancelled_by/cancelled_at server-side the
-- instant status actually changes — never trusted from the client.

create or replace function public.leave_requests_force_pending_on_insert()
returns trigger
language plpgsql
as $$
begin
  new.status := 'pending';
  new.decided_by := null;
  new.decided_at := null;
  new.cancelled_by := null;
  new.cancelled_at := null;
  return new;
end;
$$;

create trigger leave_requests_force_pending_on_insert_trigger
  before insert on public.leave_requests
  for each row
  execute function public.leave_requests_force_pending_on_insert();

-- Every legal transition and nothing else. pending -> {approved, rejected,
-- cancelled}; approved -> revoked. Enforced at the database level so a
-- direct client UPDATE (not just the RPCs in the later migration) can never
-- bypass it.
create or replace function public.leave_requests_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'pending' and new.status in ('approved', 'rejected', 'cancelled'))
    or (old.status = 'approved' and new.status = 'revoked')
  ) then
    raise exception 'invalid_leave_status_transition: % -> % is not permitted', old.status, new.status;
  end if;

  if new.status in ('approved', 'rejected') then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;

  if new.status = 'cancelled' then
    new.cancelled_by := auth.uid();
    new.cancelled_at := now();
  end if;

  return new;
end;
$$;

create trigger leave_requests_validate_transition_trigger
  before update on public.leave_requests
  for each row
  execute function public.leave_requests_validate_transition();

-- ---------------------------------------------------------------------------
-- RLS: replaces the Phase G blanket can_manage_operations-only policy set
-- with genuine, narrow employee self-service alongside the existing
-- operational-management tier — an intentional behavior change, not a
-- silent one (see the approved Phase H architecture §21/§30.4).

-- Both original Phase G policies are replaced: the old SELECT policy
-- (tenant_id = current_tenant_id(), i.e. every tenant member could read
-- every leave request) is far broader than the approved Phase H design —
-- employee.leave.view means own-only, not tenant-wide (architecture §34).
drop policy if exists leave_requests_select_within_tenant on public.leave_requests;
drop policy if exists leave_requests_write_by_manager on public.leave_requests;

create policy leave_requests_select_own_or_broad on public.leave_requests for select to authenticated
  using (
    public.can_view_leave_broad(tenant_id)
    or exists (select 1 from public.employees e where e.id = leave_requests.employee_id and e.profile_id = auth.uid())
  );

-- Self-submission for one's own employee record, or an approver logging a
-- request on someone else's behalf. Either way the row lands 'pending'
-- (see leave_requests_force_pending_on_insert above) — this policy only
-- gates "who may this request be about", not "who may set its status".
create policy leave_requests_insert on public.leave_requests for insert to authenticated
  with check (
    public.can_approve_leave(tenant_id)
    or exists (select 1 from public.employees e where e.id = leave_requests.employee_id and e.profile_id = auth.uid())
  );

-- Self-service update is narrow: only your own row, only while pending,
-- only into cancelled (leave_requests_validate_transition_trigger still
-- enforces the transition itself). Anything else requires leave.approve.
create policy leave_requests_update on public.leave_requests for update to authenticated
  using (
    public.can_approve_leave(tenant_id)
    or (
      status = 'pending'
      and exists (select 1 from public.employees e where e.id = leave_requests.employee_id and e.profile_id = auth.uid())
    )
  )
  with check (
    public.can_approve_leave(tenant_id)
    or (
      status = 'cancelled'
      and exists (select 1 from public.employees e where e.id = leave_requests.employee_id and e.profile_id = auth.uid())
    )
  );

comment on table public.leave_requests is
  'Primary leave-request entity (Phase 1) extended in Phase H with the approval lifecycle. Status starts pending (server-enforced on every INSERT) and only leave.approve holders may move it to approved/rejected/revoked; an employee may only cancel their own still-pending request. Never hard-deleted — no DELETE policy, force RLS makes that unconditional.';
