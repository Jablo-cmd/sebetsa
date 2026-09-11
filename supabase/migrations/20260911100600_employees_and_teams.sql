-- Sebetsa Phase C — Workforce
-- Employee records are NOT automatically application users: `employees.profile_id`
-- is nullable, linking to `profiles` only when that person also has app login
-- access (per the brief's "employee != application user" requirement).

create type public.employment_status as enum ('active', 'on_leave', 'suspended', 'terminated');
create type public.employment_type as enum ('full_time', 'part_time', 'contract', 'temporary');

create table public.departments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  name        text not null check (char_length(name) > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create index departments_tenant_id_idx on public.departments (tenant_id);

create trigger departments_set_updated_at
  before update on public.departments
  for each row
  execute function public.set_updated_at();

create table public.positions (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  department_id uuid references public.departments (id) on delete set null,
  title         text not null check (char_length(title) > 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (tenant_id, title)
);

create index positions_tenant_id_idx on public.positions (tenant_id);
create index positions_department_id_idx on public.positions (department_id);

create trigger positions_set_updated_at
  before update on public.positions
  for each row
  execute function public.set_updated_at();

create table public.employees (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  profile_id          uuid references public.profiles (id) on delete set null,
  employee_number     text not null,
  first_name          text not null check (char_length(first_name) > 0),
  last_name           text not null check (char_length(last_name) > 0),
  email               text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone               text,
  department_id       uuid references public.departments (id) on delete set null,
  position_id         uuid references public.positions (id) on delete set null,
  supervisor_id       uuid references public.employees (id) on delete set null,
  region_id           uuid references public.regions (id) on delete set null,
  home_site_id        uuid references public.sites (id) on delete set null,
  employment_type     public.employment_type not null default 'full_time',
  employment_status   public.employment_status not null default 'active',
  employment_start_date date not null default current_date,
  employment_end_date date,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, employee_number),
  check (employment_end_date is null or employment_end_date >= employment_start_date)
);

comment on column public.employees.profile_id is 'NULL when this employee has no application login — a workforce record is not automatically an app user.';

create index employees_tenant_id_idx on public.employees (tenant_id);
create index employees_department_id_idx on public.employees (department_id);
create index employees_home_site_id_idx on public.employees (home_site_id);
create index employees_supervisor_id_idx on public.employees (supervisor_id);
create index employees_profile_id_idx on public.employees (profile_id);

create trigger employees_set_updated_at
  before update on public.employees
  for each row
  execute function public.set_updated_at();

create table public.teams (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  site_id     uuid references public.sites (id) on delete set null,
  name        text not null check (char_length(name) > 0),
  lead_employee_id uuid references public.employees (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create index teams_tenant_id_idx on public.teams (tenant_id);
create index teams_site_id_idx on public.teams (site_id);

create trigger teams_set_updated_at
  before update on public.teams
  for each row
  execute function public.set_updated_at();

create table public.team_members (
  team_id     uuid not null references public.teams (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (team_id, employee_id)
);

create index team_members_tenant_id_idx on public.team_members (tenant_id);
create index team_members_employee_id_idx on public.team_members (employee_id);

-- Site assignments: which employees are assigned to work which site,
-- distinct from an employee's `home_site_id` default and from scheduling
-- (which says when).
create table public.site_assignments (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  site_id     uuid not null references public.sites (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  role_on_site text,
  start_date  date not null default current_date,
  end_date    date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);

create index site_assignments_tenant_id_idx on public.site_assignments (tenant_id);
create index site_assignments_site_id_idx on public.site_assignments (site_id);
create index site_assignments_employee_id_idx on public.site_assignments (employee_id);

create trigger site_assignments_set_updated_at
  before update on public.site_assignments
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: read within tenant; write by org structure managers or a site's own
-- supervisor/site_manager (site-level write is deferred to a later phase —
-- MVP write access mirrors can_manage_org_structure).
alter table public.departments enable row level security;
alter table public.departments force row level security;
alter table public.positions enable row level security;
alter table public.positions force row level security;
alter table public.employees enable row level security;
alter table public.employees force row level security;
alter table public.teams enable row level security;
alter table public.teams force row level security;
alter table public.team_members enable row level security;
alter table public.team_members force row level security;
alter table public.site_assignments enable row level security;
alter table public.site_assignments force row level security;

create policy departments_select_within_tenant on public.departments for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy departments_write_by_manager on public.departments for all to authenticated
  using (public.can_manage_org_structure(tenant_id)) with check (public.can_manage_org_structure(tenant_id));

create policy positions_select_within_tenant on public.positions for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy positions_write_by_manager on public.positions for all to authenticated
  using (public.can_manage_org_structure(tenant_id)) with check (public.can_manage_org_structure(tenant_id));

create policy employees_select_within_tenant on public.employees for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy employees_write_by_manager on public.employees for all to authenticated
  using (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user')
  with check (public.can_manage_org_structure(tenant_id) or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'hr_user');

create policy teams_select_within_tenant on public.teams for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy teams_write_by_manager on public.teams for all to authenticated
  using (public.can_manage_org_structure(tenant_id)) with check (public.can_manage_org_structure(tenant_id));

create policy team_members_select_within_tenant on public.team_members for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy team_members_write_by_manager on public.team_members for all to authenticated
  using (public.can_manage_org_structure(tenant_id)) with check (public.can_manage_org_structure(tenant_id));

create policy site_assignments_select_within_tenant on public.site_assignments for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());
create policy site_assignments_write_by_manager on public.site_assignments for all to authenticated
  using (public.can_manage_org_structure(tenant_id)) with check (public.can_manage_org_structure(tenant_id));
