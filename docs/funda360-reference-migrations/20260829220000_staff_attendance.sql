-- FND-ATT-003: Staff attendance tracking.
--
-- One row per (employee, date), mirroring attendance_records' own shape
-- exactly (one row per learner/class/date) — same daily-register model,
-- applied to staff instead of learners. Reuses the existing
-- public.attendance_status enum (present/absent/late/excused) verbatim
-- rather than inventing a parallel one: all four states apply to staff
-- attendance identically, and sharing the enum means FND-HR-004 (leave
-- management, soft-after this ticket) can simply write an 'excused'
-- staff_attendance_records row for an approved leave day without a second
-- vocabulary to keep in sync.
--
-- RBAC: reuses can_view_employees()/can_manage_employees() verbatim (the
-- exact actor set that already owns the employees directory itself), plus
-- a self-access SELECT clause — any employee can see their own attendance
-- record even without employee.view — mirroring employees_select's own
-- `profile_id = auth.uid()` clause exactly.
--
-- SECURITY DEFINER on the tenant-validation trigger — same reasoning as
-- attendance_records_validate_tenant(): reads employees, which a plain
-- teacher/non-HR role does not hold employee.view for.

create table public.staff_attendance_records (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  employee_id       uuid not null references public.employees (id) on delete cascade,
  attendance_date   date not null,
  status            public.attendance_status not null,
  notes             text,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.staff_attendance_records is 'Daily staff attendance — one row per (employee, attendance_date), same model as attendance_records but for staff. Corrections are UPDATEs; no DELETE policy, same as every other table in this schema.';

create unique index staff_attendance_records_unique_idx on public.staff_attendance_records (employee_id, attendance_date);
create index staff_attendance_records_school_id_idx on public.staff_attendance_records (school_id);
create index staff_attendance_records_employee_id_idx on public.staff_attendance_records (employee_id);
create index staff_attendance_records_date_idx on public.staff_attendance_records (attendance_date);

create trigger staff_attendance_records_set_updated_at
  before update on public.staff_attendance_records
  for each row
  execute function public.set_updated_at();

create trigger staff_attendance_records_set_created_updated_by
  before insert or update on public.staff_attendance_records
  for each row
  execute function public.set_created_updated_by();

create or replace function public.staff_attendance_records_validate_tenant()
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

create trigger staff_attendance_records_validate_tenant_trigger
  before insert or update on public.staff_attendance_records
  for each row
  execute function public.staff_attendance_records_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.staff_attendance_records enable row level security;
alter table public.staff_attendance_records force row level security;

-- Mirrors employees_select's own shape exactly: can_view_employees()
-- covers the HR/management case, the EXISTS clause is the "an employee
-- can always see their own record" self-access case.
create policy staff_attendance_records_select on public.staff_attendance_records
  for select to authenticated using (
    public.can_view_employees(school_id)
    or exists (
      select 1 from public.employees e
      where e.id = staff_attendance_records.employee_id and e.profile_id = auth.uid()
    )
  );
create policy staff_attendance_records_insert on public.staff_attendance_records
  for insert to authenticated with check (public.can_manage_employees(school_id));
create policy staff_attendance_records_update on public.staff_attendance_records
  for update to authenticated using (public.can_manage_employees(school_id)) with check (public.can_manage_employees(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete
-- is impossible for any authenticated caller. A mismarked entry is
-- corrected via UPDATE, same as attendance_records.
