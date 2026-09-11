-- FND-HR-004: Leave management (request + approval workflow), soft-after
-- FND-ATT-003.
--
-- leave_type is a closed enum of the standard South African labour-law
-- categories (annual, sick, family responsibility, unpaid) plus 'other' as
-- the escape hatch — unlike learners.gender/timetable_entries.room (open
-- free text, no taxonomy exists to defer to), leave categories genuinely
-- are a fixed, well-known list for this domain, so a closed enum is the
-- correct choice here, not an inconsistency with those other decisions.
--
-- WORKFLOW SCOPE (deliberate v1 cut, documented rather than silently
-- assumed): an employee may request their own leave (self-INSERT) or a
-- manager may log it on their behalf (e.g. a phone-called-in sick day);
-- only a manager (can_manage_employees) may ever approve, reject, or edit
-- a request afterward — there is no self-service "cancel my own pending
-- request" path in this version. An employee who needs to withdraw a
-- request asks their manager to reject it. Revisit if that friction proves
-- real; not assumed here.
--
-- Two triggers close the gaps RLS alone can't express column-by-column:
--   - leave_requests_force_pending_on_insert(): every INSERT is forced to
--     status='pending' with reviewed_* cleared, regardless of what a
--     caller sends — closes the "insert a pre-approved request" loophole
--     a plain INSERT policy alone would leave open for the manager path.
--   - leave_requests_sync_review_fields(): reviewed_by/reviewed_at are
--     always server-derived from auth.uid()/now() the moment status
--     changes to approved/rejected — never trusted from the client, same
--     "server is the source of truth for a derived field" pattern as
--     academic_interventions.resolved_at/notifications.read_at.
--
-- RBAC: reuses can_view_employees()/can_manage_employees() verbatim (no
-- new permission), plus the same employees.profile_id self-access SELECT/
-- INSERT clause staff_attendance_records already established.

create type public.leave_type as enum ('annual', 'sick', 'family_responsibility', 'unpaid', 'other');

create type public.leave_request_status as enum ('pending', 'approved', 'rejected', 'cancelled');

create table public.leave_requests (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references public.schools (id) on delete cascade,
  employee_id    uuid not null references public.employees (id) on delete cascade,
  leave_type     public.leave_type not null,
  start_date     date not null,
  end_date       date not null,
  reason         text not null check (char_length(reason) > 0),
  status         public.leave_request_status not null default 'pending',
  reviewed_by    uuid references public.profiles (id) on delete set null,
  reviewed_at    timestamptz,
  review_notes   text,
  created_by     uuid references public.profiles (id) on delete set null,
  updated_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint leave_requests_date_range_valid check (end_date >= start_date)
);

comment on table public.leave_requests is 'A leave request + its approval workflow — status starts pending (server-enforced on every INSERT, see leave_requests_force_pending_on_insert) and only a manager (can_manage_employees) may move it to approved/rejected. Never hard-deleted; no DELETE policy, same as every other table in this schema. A withdrawn request is rejected by a manager, not deleted or self-cancelled — see migration header for that scope decision.';
comment on column public.leave_requests.reviewed_by is 'Server-derived from auth.uid() the moment status changes to approved/rejected — never trusted from the client. NULL while pending.';

create index leave_requests_school_id_idx on public.leave_requests (school_id);
create index leave_requests_employee_id_idx on public.leave_requests (employee_id);
create index leave_requests_status_idx on public.leave_requests (status);
create index leave_requests_date_range_idx on public.leave_requests (start_date, end_date);

create trigger leave_requests_set_updated_at
  before update on public.leave_requests
  for each row
  execute function public.set_updated_at();

create trigger leave_requests_set_created_updated_by
  before insert or update on public.leave_requests
  for each row
  execute function public.set_created_updated_by();

create or replace function public.leave_requests_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_school_id uuid;
begin
  select school_id into v_employee_school_id from public.employees where id = new.employee_id;
  if v_employee_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: employee_id must belong to the same school';
  end if;
  return new;
end;
$$;

create trigger leave_requests_validate_tenant_trigger
  before insert or update on public.leave_requests
  for each row
  execute function public.leave_requests_validate_tenant();

create or replace function public.leave_requests_force_pending_on_insert()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.status := 'pending';
  new.reviewed_by := null;
  new.reviewed_at := null;
  new.review_notes := null;
  return new;
end;
$$;

create trigger leave_requests_force_pending_on_insert_trigger
  before insert on public.leave_requests
  for each row
  execute function public.leave_requests_force_pending_on_insert();

create or replace function public.leave_requests_sync_review_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('approved', 'rejected') and old.status is distinct from new.status then
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;

create trigger leave_requests_sync_review_fields_trigger
  before update on public.leave_requests
  for each row
  execute function public.leave_requests_sync_review_fields();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.leave_requests enable row level security;
alter table public.leave_requests force row level security;

create policy leave_requests_select on public.leave_requests
  for select to authenticated using (
    public.can_view_employees(school_id)
    or exists (
      select 1 from public.employees e
      where e.id = leave_requests.employee_id and e.profile_id = auth.uid()
    )
  );

-- Self-service request submission, or a manager logging one on someone's
-- behalf — either way it lands as 'pending' regardless (see the force-
-- pending trigger above), so this policy only needs to gate "who may this
-- request be about", not "who may set its status".
create policy leave_requests_insert on public.leave_requests
  for insert to authenticated with check (
    public.can_manage_employees(school_id)
    or exists (
      select 1 from public.employees e
      where e.id = leave_requests.employee_id and e.profile_id = auth.uid()
    )
  );

-- Manager-only: approving, rejecting, or otherwise editing a request is
-- not a self-service action in this version (see migration header).
create policy leave_requests_update on public.leave_requests
  for update to authenticated using (public.can_manage_employees(school_id)) with check (public.can_manage_employees(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete
-- is impossible for any authenticated caller.
