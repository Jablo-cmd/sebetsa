-- Sprint 2 Milestone 2 — Employee Management (Phase 1: Database)
--
-- Two tenant-scoped tables (departments, employees). employees is the HR
-- master record; profiles remains the authentication/authorization record.
-- These are deliberately separate domains, per the locked architecture
-- contract for this milestone — employees never mirrors, syncs, or
-- otherwise duplicates identity fields into profiles, and profiles is
-- never read or written by anything in this migration. first_name/
-- last_name exist only on employees.
--
-- Field names follow the same school_id convention as Academic Structure
-- (20260803150000_academic_structure.sql), for the same reason: a new
-- column on a new table, read by RLS via current_tenant_id() exactly like
-- every other tenant-scoped table.

-- ---------------------------------------------------------------------------
-- enums

create type public.employment_type as enum ('full_time', 'part_time', 'contract', 'temporary');
create type public.employment_status as enum ('active', 'on_leave', 'suspended', 'terminated');

-- ---------------------------------------------------------------------------
-- shared trigger: created_by/updated_by
--
-- Reusable across both tables in this migration, the same way
-- set_updated_at() (Milestone 3) is reused across every table. created_by
-- is set once at insert and never changes; updated_by refreshes on every
-- write. Answers "which authenticated user performed the action" — always
-- references profiles.id, never employees.id (audit is about the acting
-- user, not the HR subject of the row).
create or replace function public.set_created_updated_by()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.updated_by := auth.uid();
  elsif tg_op = 'UPDATE' then
    new.updated_by := auth.uid();
    new.created_by := old.created_by;
  end if;
  return new;
end;
$$;

comment on function public.set_created_updated_by() is
  'Populates created_by/updated_by from auth.uid() — the acting user, not the HR subject of the row. created_by is immutable after insert. Reused by departments and employees.';

-- ---------------------------------------------------------------------------
-- departments

create table public.departments (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  name         text not null check (char_length(name) > 0),
  code         text,
  description  text,
  active       boolean not null default true,
  created_by   uuid references public.profiles (id) on delete set null,
  updated_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.departments is 'Organizational/HR grouping for employees. Never hard-deleted — active=false is the archive state.';

create index departments_school_id_idx on public.departments (school_id);
create unique index departments_school_id_name_key on public.departments (school_id, lower(name));

create trigger departments_set_updated_at
  before update on public.departments
  for each row
  execute function public.set_updated_at();

create trigger departments_set_created_updated_by
  before insert or update on public.departments
  for each row
  execute function public.set_created_updated_by();

-- ---------------------------------------------------------------------------
-- employees

-- first_name/last_name are NOT NULL unconditionally — employees is the
-- sole owner of employee identity, regardless of whether profile_id is
-- set. No mirror, no sync trigger, no prevent_direct_name_change: none of
-- that exists in this design. The application resolves an employee's name
-- by querying employees directly, never profiles.
create table public.employees (
  id                       uuid primary key default gen_random_uuid(),
  school_id                uuid not null references public.schools (id) on delete cascade,
  profile_id               uuid references public.profiles (id) on delete set null,
  employee_number          text not null check (char_length(employee_number) > 0),
  first_name               text not null check (char_length(first_name) > 0),
  last_name                text not null check (char_length(last_name) > 0),
  work_email               text check (work_email is null or work_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  work_phone               text,
  id_number                text,
  date_of_birth            date,
  department_id            uuid references public.departments (id),
  job_title                text,
  employment_type          public.employment_type,
  employment_status        public.employment_status not null default 'active',
  hire_date                date not null,
  termination_date         date,
  reports_to_employee_id   uuid references public.employees (id),
  emergency_contact_name   text,
  emergency_contact_phone  text,
  created_by               uuid references public.profiles (id) on delete set null,
  updated_by               uuid references public.profiles (id) on delete set null,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  constraint employees_termination_after_hire check (termination_date is null or termination_date >= hire_date),
  constraint employees_no_self_report check (id <> reports_to_employee_id)
);

comment on table public.employees is 'The HR master record. Independent of login status — profile_id is optional. Never hard-deleted — employment_status=terminated is the archive state. Owns first_name/last_name exclusively; profiles is never read or written by this table or its triggers.';
comment on column public.employees.profile_id is 'Optional link to a login account. ON DELETE SET NULL, never CASCADE — the employee record must survive profile deletion (retention requirement).';
comment on column public.employees.department_id is 'Must belong to the same school_id — enforced by employees_validate_department_school().';
comment on column public.employees.reports_to_employee_id is 'Must belong to the same school_id and must not create a reporting cycle — enforced by employees_validate_reports_to(). Direct self-reference additionally blocked by employees_no_self_report.';

create index employees_school_id_idx on public.employees (school_id);
create index employees_school_id_employment_status_idx on public.employees (school_id, employment_status);
create index employees_school_id_department_id_idx on public.employees (school_id, department_id);
create index employees_reports_to_employee_id_idx on public.employees (reports_to_employee_id);
create index employees_profile_id_idx on public.employees (profile_id);

create unique index employees_school_id_employee_number_key on public.employees (school_id, employee_number);
create unique index employees_profile_id_key on public.employees (profile_id) where profile_id is not null;

create trigger employees_set_updated_at
  before update on public.employees
  for each row
  execute function public.set_updated_at();

create trigger employees_set_created_updated_by
  before insert or update on public.employees
  for each row
  execute function public.set_created_updated_by();

-- Closes the same FK-doesn't-respect-RLS gap already fixed twice in
-- Academic Structure (terms_validate_academic_year_school,
-- classes_validate_grade_school) — a foreign key alone doesn't check that
-- the caller could ever SELECT the referenced row under RLS.
create or replace function public.employees_validate_department_school()
returns trigger
language plpgsql
as $$
declare
  v_department_school_id uuid;
begin
  if new.department_id is null then
    return new;
  end if;
  select school_id into v_department_school_id from public.departments where id = new.department_id;
  if v_department_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: department_id must belong to the same school';
  end if;
  return new;
end;
$$;

create trigger employees_validate_department_school_trigger
  before insert or update on public.employees
  for each row
  execute function public.employees_validate_department_school();

create or replace function public.employees_validate_profile_tenant()
returns trigger
language plpgsql
as $$
declare
  v_profile_tenant_id uuid;
begin
  if new.profile_id is null then
    return new;
  end if;
  select tenant_id into v_profile_tenant_id from public.profiles where id = new.profile_id;
  if v_profile_tenant_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: profile_id must belong to the same school';
  end if;
  return new;
end;
$$;

create trigger employees_validate_profile_tenant_trigger
  before insert or update on public.employees
  for each row
  execute function public.employees_validate_profile_tenant();

-- reports_to_employee_id: tenant match AND cycle detection in one trigger
-- (both concerns center on the same column and the same lookup path).
-- Direct self-reference is separately, cheaply blocked by the
-- employees_no_self_report check constraint above; this trigger covers
-- the general multi-hop case a check constraint cannot express.
create or replace function public.employees_validate_reports_to()
returns trigger
language plpgsql
as $$
declare
  v_manager_school_id uuid;
  v_cycle_count int;
begin
  if new.reports_to_employee_id is null then
    return new;
  end if;

  select school_id into v_manager_school_id from public.employees where id = new.reports_to_employee_id;
  if v_manager_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: reports_to_employee_id must belong to the same school';
  end if;

  with recursive chain as (
    select id, reports_to_employee_id
    from public.employees
    where id = new.reports_to_employee_id
    union all
    select e.id, e.reports_to_employee_id
    from public.employees e
    join chain c on e.id = c.reports_to_employee_id
  )
  select count(*) into v_cycle_count from chain where id = new.id;

  if v_cycle_count > 0 then
    raise exception 'insufficient_privilege: reports_to_employee_id would create a reporting cycle';
  end if;

  return new;
end;
$$;

create trigger employees_validate_reports_to_trigger
  before insert or update on public.employees
  for each row
  execute function public.employees_validate_reports_to();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.departments enable row level security;
alter table public.departments force row level security;
alter table public.employees enable row level security;
alter table public.employees force row level security;

-- Mirrors the app-level employee.view permission (ROLE_PERMISSIONS in
-- src/features/rbac/constants/rolePermissions.ts) — school_owner,
-- principal, hr_manager, or any platform admin. Keep in sync manually.
create or replace function public.can_view_employees(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal', 'hr_manager')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_employees(uuid) is
  'Mirrors the app-level employee.view permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- Mirrors the app-level employee.manage permission — school_owner and
-- hr_manager only (narrower than view — principal can see the directory
-- but not manage HR records), or any platform admin.
create or replace function public.can_manage_employees(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'hr_manager')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_employees(uuid) is
  'Mirrors the app-level employee.manage permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

grant execute on function public.can_view_employees(uuid) to authenticated;
grant execute on function public.can_manage_employees(uuid) to authenticated;

-- departments: no self-access concept (not owned by an individual).
create policy departments_select on public.departments
  for select to authenticated using (public.can_view_employees(school_id));
create policy departments_insert on public.departments
  for insert to authenticated with check (public.can_manage_employees(school_id));
create policy departments_update on public.departments
  for update to authenticated using (public.can_manage_employees(school_id)) with check (public.can_manage_employees(school_id));

-- employees: can_view_employees covers the directory case; the
-- `profile_id = auth.uid()` clause is the self-access case (any employee
-- can see their own record even without employee.view), the same shape as
-- profiles_select_own_or_tenant_or_platform_admin's own `id = auth.uid()`
-- clause. can_manage_employees is a strict subset of can_view_employees'
-- role list, so it is not repeated in the SELECT policy.
create policy employees_select on public.employees
  for select to authenticated using (public.can_view_employees(school_id) or profile_id = auth.uid());
create policy employees_insert on public.employees
  for insert to authenticated with check (public.can_manage_employees(school_id));
create policy employees_update on public.employees
  for update to authenticated using (public.can_manage_employees(school_id)) with check (public.can_manage_employees(school_id));

-- No DELETE policy on either table — combined with FORCE ROW LEVEL
-- SECURITY, hard delete is impossible for any authenticated caller.
-- employment_status = 'terminated' / departments.active = false are the
-- only archive states.

-- ---------------------------------------------------------------------------
-- RPCs

-- provision_employee_login() is NOT included in this migration.
-- BLOCKED — see Phase 1 delivery report: profiles.first_name/last_name are
-- NOT NULL with a non-empty CHECK constraint (20260802125402_create_profiles.sql,
-- lines 17-18), and the locked architecture for this milestone forbids
-- writing employee name data into profiles under any circumstances. There
-- is no value this function can legally insert into those two columns.
-- Awaiting instruction before implementing this RPC.

-- terminate_employee: atomically sets employment_status and, if a login is
-- linked, deactivates it in the same transaction — a terminated employee
-- must never be left with an active login.
create or replace function public.terminate_employee(
  p_employee_id uuid,
  p_termination_date date
)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_profile_id uuid;
  v_result public.employees;
begin
  select school_id, profile_id into v_school_id, v_profile_id from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this school';
  end if;

  update public.employees
    set employment_status = 'terminated', termination_date = p_termination_date
    where id = p_employee_id
    returning * into v_result;

  if v_profile_id is not null then
    update public.profiles set status = 'inactive' where id = v_profile_id;
  end if;

  return v_result;
end;
$$;

comment on function public.terminate_employee(uuid, date) is
  'Sets employment_status=terminated and, if a login is linked, profiles.status=inactive, in one transaction. The employee record is never deleted.';

grant execute on function public.terminate_employee(uuid, date) to authenticated;

-- reactivate_employee: employment status only. Deliberately does not
-- reactivate a linked login — a login may have been deactivated for a
-- reason unrelated to this employment change.
create or replace function public.reactivate_employee(p_employee_id uuid)
returns public.employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_result public.employees;
begin
  select school_id into v_school_id from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this school';
  end if;

  update public.employees
    set employment_status = 'active', termination_date = null
    where id = p_employee_id
    returning * into v_result;

  return v_result;
end;
$$;

comment on function public.reactivate_employee(uuid) is
  'Sets employment_status=active. Deliberately does not touch a linked profile''s status — see terminate_employee for the asymmetric reasoning.';

grant execute on function public.reactivate_employee(uuid) to authenticated;
