-- Sebetsa Phase G — Scheduling & Workforce Availability
--
-- Two responsibilities, per the approved Phase G architecture:
--
-- 1. Harden the pre-existing scheduling schema (shifts, shift_substitutions,
--    attendance_records, leave_requests — created in
--    20260911101000_scheduling_and_attendance.sql, before the Phase F
--    cross-tenant-validation / audit-trigger pattern existed) up to the same
--    standard every other operational table now has.
--
-- 2. Add the small number of genuinely new pieces: shift_definitions
--    (reusable shift templates), employee_availability +
--    employee_availability_exceptions (the availability model), and a
--    database-enforced overlap-prevention constraint on shifts.
--
-- Additive only — no historical migration is modified, no data is dropped.
-- shifts/shift_substitutions/attendance_records/leave_requests hold no real
-- rows in hosted at the time of this migration (confirmed via the Phase F
-- hosted test-data cleanup), so backfilling triggers onto them is safe.

-- ---------------------------------------------------------------------------
-- Required for the shift overlap-prevention exclusion constraint (§7/§9 of
-- the approved architecture) — provides gist support for the `=` operator
-- class on uuid, needed to exclude on (employee_id, time range) together.
create extension if not exists btree_gist;

-- ---------------------------------------------------------------------------
-- shift_definitions: reusable shift templates ("Day Shift, 08:00-17:00").
-- A shift may optionally reference one; ad-hoc shifts with no template
-- remain fully valid (nullable FK added to shifts below).

create table public.shift_definitions (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.organizations (id) on delete cascade,
  name           text not null check (char_length(name) > 0),
  start_time     time not null,
  end_time       time not null,
  is_overnight   boolean not null default false,
  break_minutes  integer not null default 0 check (break_minutes >= 0),
  status         public.entity_status not null default 'active',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (tenant_id, name)
);

comment on table public.shift_definitions is 'Reusable shift templates (name + time window). shifts.shift_definition_id references this optionally — a shift never depends on a definition existing.';

create index shift_definitions_tenant_id_idx on public.shift_definitions (tenant_id);

create trigger shift_definitions_set_updated_at
  before update on public.shift_definitions
  for each row
  execute function public.set_updated_at();

alter table public.shift_definitions enable row level security;
alter table public.shift_definitions force row level security;

create policy shift_definitions_select_within_tenant on public.shift_definitions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy shift_definitions_write_by_manager on public.shift_definitions for all to authenticated
  using (public.can_manage_org_structure(tenant_id)) with check (public.can_manage_org_structure(tenant_id));

create trigger shift_definitions_audit_log
  after insert or update on public.shift_definitions
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- shifts: extend with the optional template link, cross-tenant validation,
-- audit coverage, and DB-enforced overlap prevention.

alter table public.shifts add column shift_definition_id uuid references public.shift_definitions (id) on delete set null;

create index shifts_shift_definition_id_idx on public.shifts (shift_definition_id);

create or replace function public.validate_shift_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  if new.supervisor_id is not null and not exists (
    select 1 from public.employees where id = new.supervisor_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: supervisor % does not belong to tenant %', new.supervisor_id, new.tenant_id;
  end if;

  if new.shift_definition_id is not null and not exists (
    select 1 from public.shift_definitions where id = new.shift_definition_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: shift definition % does not belong to tenant %', new.shift_definition_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger shifts_validate_tenant_refs
  before insert or update on public.shifts
  for each row
  execute function public.validate_shift_tenant_refs();

create trigger shifts_audit_log
  after insert or update on public.shifts
  for each row
  execute function public.audit_log_from_trigger();

-- Overlap prevention: an employee cannot hold two non-cancelled shifts whose
-- time ranges intersect. tstzrange defaults to inclusive-start/exclusive-end
-- ([)), so back-to-back shifts (one ending exactly when the next starts) are
-- correctly treated as non-overlapping.
alter table public.shifts add constraint shifts_no_overlap
  exclude using gist (
    employee_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (status <> 'cancelled');

comment on constraint shifts_no_overlap on public.shifts is 'Database-enforced conflict prevention: rejects any insert/update that would give one employee two overlapping non-cancelled shifts. Requires btree_gist (enabled above).';

-- ---------------------------------------------------------------------------
-- shift_substitutions: cross-tenant validation + audit (schema unchanged —
-- its reassignment-as-a-new-row shape was already correct).

create or replace function public.validate_shift_substitution_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.shifts where id = new.shift_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: shift % does not belong to tenant %', new.shift_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.employees where id = new.original_employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.original_employee_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.employees where id = new.substitute_employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.substitute_employee_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger shift_substitutions_validate_tenant_refs
  before insert or update on public.shift_substitutions
  for each row
  execute function public.validate_shift_substitution_tenant_refs();

create trigger shift_substitutions_audit_log
  after insert or update on public.shift_substitutions
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- attendance_records: cross-tenant validation + audit (schema/frontend
-- unchanged — Attendance is not being rebuilt in this phase).

create or replace function public.validate_attendance_record_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  if new.shift_id is not null and not exists (
    select 1 from public.shifts where id = new.shift_id and tenant_id = new.tenant_id
  ) then
    raise exception 'cross_tenant_reference: shift % does not belong to tenant %', new.shift_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger attendance_records_validate_tenant_refs
  before insert or update on public.attendance_records
  for each row
  execute function public.validate_attendance_record_tenant_refs();

create trigger attendance_records_audit_log
  after insert or update on public.attendance_records
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- leave_requests: cross-tenant validation + audit only. No leave workflow
-- (approval, balances, types) is introduced — this is a gap-close so Phase H
-- does not inherit an already-known integrity gap.

create or replace function public.validate_leave_request_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger leave_requests_validate_tenant_refs
  before insert or update on public.leave_requests
  for each row
  execute function public.validate_leave_request_tenant_refs();

create trigger leave_requests_audit_log
  after insert or update on public.leave_requests
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- employee_availability: weekly recurring availability. Deliberately small
-- — no rules engine, no recurrence expressions.

create table public.employee_availability (
  id           uuid primary key default gen_random_uuid(),
  tenant_id    uuid not null references public.organizations (id) on delete cascade,
  employee_id  uuid not null references public.employees (id) on delete cascade,
  day_of_week  smallint not null check (day_of_week between 0 and 6), -- 0 = Sunday
  start_time   time not null,
  end_time     time not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (employee_id, day_of_week, start_time)
);

comment on table public.employee_availability is 'Recurring weekly availability windows. More than one row per employee/day is allowed (split shifts); overlap within a day is an application-level warning, not a DB constraint.';

create index employee_availability_tenant_id_idx on public.employee_availability (tenant_id);
create index employee_availability_employee_id_idx on public.employee_availability (employee_id);

create trigger employee_availability_set_updated_at
  before update on public.employee_availability
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- employee_availability_exceptions: date-specific overrides. This is also
-- the integration seam a future Phase H leave-approval flow would write
-- into (is_available = false per approved leave date) — no leave workflow
-- is implemented here.

create table public.employee_availability_exceptions (
  id              uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null references public.organizations (id) on delete cascade,
  employee_id     uuid not null references public.employees (id) on delete cascade,
  exception_date  date not null,
  is_available    boolean not null,
  start_time      time,
  end_time        time,
  reason          text,
  created_at      timestamptz not null default now(),
  unique (employee_id, exception_date)
);

comment on table public.employee_availability_exceptions is 'One row per employee per date that overrides the recurring pattern. is_available=false means unavailable all day; is_available=true with a narrower start_time/end_time means available only during that window.';

create index employee_availability_exceptions_tenant_id_idx on public.employee_availability_exceptions (tenant_id);
create index employee_availability_exceptions_employee_id_idx on public.employee_availability_exceptions (employee_id);

-- Shared cross-tenant validation for both availability tables — identical
-- check (employee_id must belong to new.tenant_id) in both cases.
create or replace function public.validate_employee_availability_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.employees where id = new.employee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger employee_availability_validate_tenant_refs
  before insert or update on public.employee_availability
  for each row
  execute function public.validate_employee_availability_tenant_refs();

create trigger employee_availability_exceptions_validate_tenant_refs
  before insert or update on public.employee_availability_exceptions
  for each row
  execute function public.validate_employee_availability_tenant_refs();

-- RLS: read within tenant. Write by the operational-management tier, OR the
-- employee managing their own availability (self-service, matching the
-- profile.update_own shape) — never by a client-supplied employee id, always
-- resolved server-side via employees.profile_id = auth.uid(). Deliberately
-- unaudited (see migration header) — high-frequency, low-privilege data.

alter table public.employee_availability enable row level security;
alter table public.employee_availability force row level security;

create policy employee_availability_select_within_tenant on public.employee_availability for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy employee_availability_write on public.employee_availability for all to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = employee_availability.employee_id and e.profile_id = auth.uid())
  )
  with check (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = employee_availability.employee_id and e.profile_id = auth.uid())
  );

alter table public.employee_availability_exceptions enable row level security;
alter table public.employee_availability_exceptions force row level security;

create policy employee_availability_exceptions_select_within_tenant on public.employee_availability_exceptions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy employee_availability_exceptions_write on public.employee_availability_exceptions for all to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = employee_availability_exceptions.employee_id and e.profile_id = auth.uid())
  )
  with check (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = employee_availability_exceptions.employee_id and e.profile_id = auth.uid())
  );
