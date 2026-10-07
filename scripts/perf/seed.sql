-- Performance baseline dataset: one realistic tenant. Deterministic (no random()). Run as the table owner against a
-- DISPOSABLE database built from the migrations. Bulk-loaded with triggers disabled (session_replication_role = replica)
-- for speed; every row is still internally consistent (tenant, site, employee ids line up).
--   :regions :clients :sites :employees :days   are psql variables (see baseline.sh)
\set ON_ERROR_STOP on
set session_replication_role = replica;

insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-00000000aa01', 'Perf Org', 'active');

insert into public.regions (id, tenant_id, name, code)
select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid, '00000000-0000-0000-0000-00000000aa01', 'Region ' || g, 'R' || g
from generate_series(1, :regions) g;

insert into public.clients (id, tenant_id, region_id, name)
select ('00000000-0000-0000-0002-' || lpad(g::text, 12, '0'))::uuid, '00000000-0000-0000-0000-00000000aa01',
       ('00000000-0000-0000-0001-' || lpad(((g % :regions) + 1)::text, 12, '0'))::uuid, 'Client ' || g
from generate_series(1, :clients) g;

insert into public.sites (id, tenant_id, client_id, region_id, name, status)
select ('00000000-0000-0000-0003-' || lpad(g::text, 12, '0'))::uuid, '00000000-0000-0000-0000-00000000aa01',
       ('00000000-0000-0000-0002-' || lpad(((g % :clients) + 1)::text, 12, '0'))::uuid,
       ('00000000-0000-0000-0001-' || lpad(((g % :regions) + 1)::text, 12, '0'))::uuid, 'Site ' || lpad(g::text, 5, '0'), 'active'
from generate_series(1, :sites) g;

-- Three real sign-in identities for RLS-realistic measurement: organisation administrator, site manager (scoped), employee.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ab01', 'authenticated', 'authenticated', 'perf-admin@example.com', 'x', now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ab02', 'authenticated', 'authenticated', 'perf-sitemgr@example.com', 'x', now(), '{"role":"site_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ab03', 'authenticated', 'authenticated', 'perf-employee@example.com', 'x', now(), '{"role":"employee"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000aa01', 'Perf', 'Admin', 'perf-admin@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000aa01', 'Perf', 'SiteMgr', 'perf-sitemgr@example.com', 'site_manager', 'active'),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000aa01', 'Perf', 'Employee', 'perf-employee@example.com', 'employee', 'active');

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, region_id, home_site_id, employment_status, employment_start_date)
select ('00000000-0000-0000-0004-' || lpad(g::text, 12, '0'))::uuid, '00000000-0000-0000-0000-00000000aa01',
       case g when 1 then '00000000-0000-0000-0000-00000000ab03'::uuid else null end,
       'E' || lpad(g::text, 6, '0'),
       (array['Thabo','Naledi','Sipho','Lerato','Johan','Aisha','Pieter','Zanele','Kagiso','Anele'])[1 + g % 10],
       (array['Mokoena','Dlamini','Naidoo','van der Merwe','Khumalo','Molefe','Pillay','Botha','Sithole','Nkosi'])[1 + (g / 10) % 10] || ' ' || g,
       ('00000000-0000-0000-0001-' || lpad(((g % :regions) + 1)::text, 12, '0'))::uuid,
       ('00000000-0000-0000-0003-' || lpad(((g % :sites) + 1)::text, 12, '0'))::uuid,
       'active', date '2024-01-01'
from generate_series(1, :employees) g;

-- Scope for the site manager: a fixed set of sites (a region's worth).
insert into public.user_scopes (tenant_id, profile_id, scope_type, scope_id)
values ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-00000000ab02', 'region', '00000000-0000-0000-0001-000000000001');

-- Shifts: each employee works every day of the window at their home site (employees x days rows).
insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at, status)
select gen_random_uuid(), '00000000-0000-0000-0000-00000000aa01', e.home_site_id, e.id,
       (current_date - (:days - 1) + d)::timestamptz + interval '6 hours', (current_date - (:days - 1) + d)::timestamptz + interval '14 hours', 'scheduled'
from public.employees e cross join generate_series(0, :days - 1) d where e.tenant_id = '00000000-0000-0000-0000-00000000aa01';

-- Attendance: ~85% of past shifts.
insert into public.attendance_records (id, tenant_id, shift_id, site_id, employee_id, status, clock_in_at, clock_out_at, late_minutes, worked_minutes, created_at)
select gen_random_uuid(), s.tenant_id, s.id, s.site_id, s.employee_id,
       case when (row_number() over ()) % 12 = 0 then 'late' else 'present' end::public.attendance_status,
       s.starts_at + interval '2 minutes', s.ends_at, 0, 480, s.starts_at
from public.shifts s where s.starts_at < now() and (hashtext(s.id::text) % 100) < 85;

-- Tasks: ~3 per employee, mixed statuses, some overdue.
insert into public.tasks (id, tenant_id, site_id, assignee_id, title, priority, status, due_at, created_at)
select gen_random_uuid(), '00000000-0000-0000-0000-00000000aa01', e.home_site_id, e.id, 'Task ' || e.employee_number || '-' || t,
       'normal', (array['open','in_progress','completed','verified','open'])[1 + (hashtext(e.id::text) + t) % 5 ]::public.task_status,
       now() + ((hashtext(e.id::text) + t) % 20 - 10) * interval '1 day', now() - interval '20 days'
from public.employees e cross join generate_series(1, 3) t;

-- Leave: one request per 5 employees, mixed.
insert into public.leave_types (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000ac01', '00000000-0000-0000-0000-00000000aa01', 'Annual');
insert into public.leave_requests (id, tenant_id, employee_id, leave_type_id, start_date, end_date, status, created_at)
select gen_random_uuid(), '00000000-0000-0000-0000-00000000aa01', e.id, '00000000-0000-0000-0000-00000000ac01',
       current_date + (hashtext(e.id::text) % 30), current_date + (hashtext(e.id::text) % 30) + 2,
       (array['pending','approved','approved','rejected'])[1 + abs(hashtext(e.id::text)) % 4]::public.leave_status, now() - interval '5 days'
from public.employees e where (hashtext(e.id::text) % 5) = 0;

reset session_replication_role;
analyze;
