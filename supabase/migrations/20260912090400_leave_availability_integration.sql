-- Sebetsa Phase H — Leave & Absence, migration 5 of 6.
--
-- Wires approved leave into the Phase G integration seam
-- (employee_availability_exceptions), per the approved architecture §14-17:
-- the leave request is the source of truth, the exception row is generated
-- from it (never authored independently), and it is distinguishable from a
-- manual exception via leave_request_id.

alter table public.employee_availability_exceptions
  add column leave_request_id uuid references public.leave_requests (id) on delete cascade;

create index employee_availability_exceptions_leave_request_id_idx
  on public.employee_availability_exceptions (leave_request_id);

comment on column public.employee_availability_exceptions.leave_request_id is
  'NULL = a manual exception (Phase G behavior, unchanged). Non-null = generated from that approved leave request by leave_requests_sync_availability_exceptions() — never hand-edited; write access to leave-generated rows is restricted to that trigger''s SECURITY DEFINER context (see the updated write policy below).';

-- The Phase G self-service/manager write policy allowed writing ANY
-- exception row, including one with a leave_request_id — close that: a
-- client (self-service employee or manager) may only write MANUAL
-- exceptions (leave_request_id is null). Leave-derived rows are exclusively
-- managed by the SECURITY DEFINER sync function below.
drop policy if exists employee_availability_exceptions_write on public.employee_availability_exceptions;

create policy employee_availability_exceptions_write on public.employee_availability_exceptions for all to authenticated
  using (
    leave_request_id is null
    and (
      public.can_manage_operations(tenant_id)
      or exists (select 1 from public.employees e where e.id = employee_availability_exceptions.employee_id and e.profile_id = auth.uid())
    )
  )
  with check (
    leave_request_id is null
    and (
      public.can_manage_operations(tenant_id)
      or exists (select 1 from public.employees e where e.id = employee_availability_exceptions.employee_id and e.profile_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------------------
-- Generation/retraction. One exception row per date in the leave's range
-- (half-day leave narrows start_time/end_time on that single day rather
-- than adding a separate row — the existing is_available=true + narrower
-- start_time/end_time shape from Phase G already models "unavailable
-- outside this window").
--
-- AFTER UPDATE only (the request must already exist and be persisted;
-- there is no "approved on insert" path since every insert is forced to
-- pending — see the lifecycle migration). SECURITY DEFINER so it can write
-- leave_request_id-tagged rows the client-facing policy above forbids.

create or replace function public.leave_requests_sync_availability_exceptions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    v_date := new.start_date;
    while v_date <= new.end_date loop
      insert into public.employee_availability_exceptions
        (tenant_id, employee_id, exception_date, is_available, start_time, end_time, reason, leave_request_id)
      values (
        new.tenant_id,
        new.employee_id,
        v_date,
        case
          when new.is_half_day and new.half_day_period = 'am' then true
          when new.is_half_day and new.half_day_period = 'pm' then true
          else false
        end,
        case when new.is_half_day and new.half_day_period = 'pm' then '00:00'::time end,
        case when new.is_half_day and new.half_day_period = 'am' then '12:00'::time end,
        'Approved leave',
        new.id
      )
      -- If a manual exception (leave_request_id is null) already occupies
      -- this date, it is left untouched (the WHERE predicate excludes it
      -- from the DO UPDATE, so the INSERT is silently skipped for that
      -- date) — a manual exception is never overwritten by leave approval,
      -- symmetric with revocation never deleting one. Re-approving the
      -- same request (idempotent re-run) still refreshes its own row.
      on conflict (employee_id, exception_date) do update set
        is_available = excluded.is_available,
        start_time = excluded.start_time,
        end_time = excluded.end_time,
        reason = excluded.reason,
        leave_request_id = excluded.leave_request_id
      where public.employee_availability_exceptions.leave_request_id = new.id;

      v_date := v_date + 1;
    end loop;
  elsif old.status = 'approved' and new.status = 'revoked' then
    delete from public.employee_availability_exceptions
    where leave_request_id = new.id;
  end if;

  return new;
end;
$$;

comment on function public.leave_requests_sync_availability_exceptions() is
  'Generates one employee_availability_exceptions row per leave date on approval (half-day AM/PM narrows the window on that single day, per Phase G''s existing is_available=true + narrower start_time/end_time shape), and deletes only its own leave-tagged rows on revocation. Never touches a manual exception (leave_request_id is null) that happens to fall on the same date — the ON CONFLICT guard skips overwriting one.';

create trigger leave_requests_sync_availability_exceptions_trigger
  after update on public.leave_requests
  for each row
  execute function public.leave_requests_sync_availability_exceptions();
