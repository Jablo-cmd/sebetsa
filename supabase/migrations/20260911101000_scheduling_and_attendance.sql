-- Sebetsa Phase 1 (remainder) — Scheduling & Attendance
-- Schedule answers WHO/WHERE/WHEN; attendance is a separate, later fact
-- (what actually happened), never derived by mutating the schedule row.

create type public.shift_status as enum ('scheduled', 'confirmed', 'cancelled', 'completed');
create type public.attendance_status as enum ('present', 'late', 'absent', 'excused', 'unconfirmed');
create type public.leave_status as enum ('pending', 'approved', 'rejected', 'cancelled');

create table public.shifts (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  site_id       uuid not null references public.sites (id) on delete cascade,
  employee_id   uuid not null references public.employees (id) on delete cascade,
  supervisor_id uuid references public.employees (id) on delete set null,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  status        public.shift_status not null default 'scheduled',
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (ends_at > starts_at)
);

comment on table public.shifts is 'A planned assignment of one employee to one site for a time window. Recurring schedules are represented as multiple generated rows, not a separate recurrence table, in this MVP.';

create index shifts_tenant_id_idx on public.shifts (tenant_id);
create index shifts_site_id_starts_at_idx on public.shifts (site_id, starts_at);
create index shifts_employee_id_starts_at_idx on public.shifts (employee_id, starts_at);

create trigger shifts_set_updated_at
  before update on public.shifts
  for each row
  execute function public.set_updated_at();

-- A shift may be reassigned from one employee to another (a substitution),
-- tracked as its own row rather than overwriting shifts.employee_id so the
-- original assignment stays visible in history.
create table public.shift_substitutions (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  shift_id            uuid not null references public.shifts (id) on delete cascade,
  original_employee_id uuid not null references public.employees (id) on delete cascade,
  substitute_employee_id uuid not null references public.employees (id) on delete cascade,
  reason              text,
  created_at          timestamptz not null default now()
);

create index shift_substitutions_tenant_id_idx on public.shift_substitutions (tenant_id);
create index shift_substitutions_shift_id_idx on public.shift_substitutions (shift_id);

-- Attendance: a separate fact from the schedule. One row per employee per
-- shift (or an unscheduled/ad-hoc attendance row with shift_id null, for a
-- site that hasn't been fully scheduled yet).
create table public.attendance_records (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  shift_id      uuid references public.shifts (id) on delete set null,
  site_id       uuid not null references public.sites (id) on delete cascade,
  employee_id   uuid not null references public.employees (id) on delete cascade,
  status        public.attendance_status not null default 'unconfirmed',
  clock_in_at   timestamptz,
  clock_out_at  timestamptz,
  recorded_by   uuid references public.profiles (id) on delete set null,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (clock_out_at is null or clock_in_at is null or clock_out_at >= clock_in_at)
);

create index attendance_records_tenant_id_idx on public.attendance_records (tenant_id);
create index attendance_records_shift_id_idx on public.attendance_records (shift_id);
create index attendance_records_employee_id_idx on public.attendance_records (employee_id, created_at);
create index attendance_records_site_id_idx on public.attendance_records (site_id, created_at);

create trigger attendance_records_set_updated_at
  before update on public.attendance_records
  for each row
  execute function public.set_updated_at();

-- Leave requests (carried forward from Funda360's staff leave-management
-- shape, generalized off "staff" onto employees).
create table public.leave_requests (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  employee_id   uuid not null references public.employees (id) on delete cascade,
  start_date    date not null,
  end_date      date not null,
  reason        text,
  status        public.leave_status not null default 'pending',
  decided_by    uuid references public.profiles (id) on delete set null,
  decided_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (end_date >= start_date)
);

create index leave_requests_tenant_id_idx on public.leave_requests (tenant_id);
create index leave_requests_employee_id_idx on public.leave_requests (employee_id);
create index leave_requests_status_idx on public.leave_requests (status);

create trigger leave_requests_set_updated_at
  before update on public.leave_requests
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: read within tenant. Write by org structure managers, or an
-- employee's own supervisor chain / self-service for their own attendance
-- clock-in — kept simple for the MVP (full manager set), site-level
-- supervisor scoping is a Phase 2 refinement once site_manager/supervisor
-- assignment data is richer.
alter table public.shifts enable row level security;
alter table public.shifts force row level security;
alter table public.shift_substitutions enable row level security;
alter table public.shift_substitutions force row level security;
alter table public.attendance_records enable row level security;
alter table public.attendance_records force row level security;
alter table public.leave_requests enable row level security;
alter table public.leave_requests force row level security;

create or replace function public.can_manage_operations(target_tenant_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_tenant_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('organization_administrator', 'operations_manager', 'regional_manager', 'site_manager', 'supervisor')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_operations(uuid) is
  'True for any operational management tier (org admin through supervisor) of the target tenant, or a platform admin. Governs writes to scheduling/attendance/leave.';

grant execute on function public.can_manage_operations(uuid) to authenticated;

create policy shifts_select_within_tenant on public.shifts for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy shifts_write_by_manager on public.shifts for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create policy shift_substitutions_select_within_tenant on public.shift_substitutions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy shift_substitutions_write_by_manager on public.shift_substitutions for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create policy attendance_records_select_within_tenant on public.attendance_records for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy attendance_records_write_by_manager on public.attendance_records for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));

create policy leave_requests_select_within_tenant on public.leave_requests for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy leave_requests_write_by_manager on public.leave_requests for all to authenticated
  using (public.can_manage_operations(tenant_id)) with check (public.can_manage_operations(tenant_id));
