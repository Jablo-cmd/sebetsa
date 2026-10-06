-- Additional fixtures for the Employee Management regression suite. Builds
-- on 02_fixtures.sql (School A/B, teacher 11111111, school_owner 22222222,
-- teacher 33333333 in School B, platform admin 44444444).

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '77777777-7777-7777-7777-777777777777', 'authenticated', 'authenticated',
   'principal.a1@schoola.test', jsonb_build_object('role', 'principal', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '88888888-8888-8888-8888-888888888888', 'authenticated', 'authenticated',
   'hr.a1@schoola.test', jsonb_build_object('role', 'hr_manager', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('77777777-7777-7777-7777-777777777777', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Principal', 'A1', 'principal.a1@schoola.test', 'principal', 'active'),
  ('88888888-8888-8888-8888-888888888888', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'HR', 'A1', 'hr.a1@schoola.test', 'hr_manager', 'active');

insert into public.departments (id, school_id, name) values
  ('dddd1111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Finance'),
  ('dddd2222-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Finance');

-- Manager employee (no login), a subordinate, and an employee linked to
-- the existing teacher profile (11111111) for self-access testing.
insert into public.employees (id, school_id, department_id, employee_number, first_name, last_name, hire_date) values
  ('eeee1111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'dddd1111-0000-0000-0000-000000000001', 'EMP-A001', 'Manager', 'A', '2024-01-01');

insert into public.employees (id, school_id, department_id, employee_number, first_name, last_name, hire_date, reports_to_employee_id, profile_id) values
  ('eeee1111-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'dddd1111-0000-0000-0000-000000000001', 'EMP-A002', 'Teacher', 'A1', '2024-02-01', 'eeee1111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

insert into public.employees (id, school_id, employee_number, first_name, last_name, hire_date) values
  ('eeee2222-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'EMP-B001', 'Teacher', 'B1', '2024-01-01');

-- Dedicated, disposable user + employee for the ON DELETE SET NULL test —
-- deliberately NOT reusing 11111111 (a shared fixture other test files,
-- e.g. profiles_tenant_id_protection.test.sql, depend on existing).
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '99999999-9999-9999-9999-999999999999', 'authenticated', 'authenticated',
   'disposable.a1@schoola.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('99999999-9999-9999-9999-999999999999', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Disposable', 'A1', 'disposable.a1@schoola.test', 'teacher', 'active');

insert into public.employees (id, school_id, employee_number, first_name, last_name, hire_date, profile_id) values
  ('eeee1111-0000-0000-0000-000000000099', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EMP-A099', 'Disposable', 'Link', '2024-01-01', '99999999-9999-9999-9999-999999999999');

-- Second, separate disposable user + employee for the terminate/reactivate
-- cascade tests — deliberately NOT the shared 11111111 fixture, since
-- terminate_employee mutates the linked profile's status, which would
-- otherwise corrupt profiles_tenant_id_protection.test.sql's assumptions
-- about that user (this was caught by actually running the harness).
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '99999999-9999-9999-9999-999999999998', 'authenticated', 'authenticated',
   'disposable.a2@schoola.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('99999999-9999-9999-9999-999999999998', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Disposable', 'A2', 'disposable.a2@schoola.test', 'teacher', 'active');

insert into public.employees (id, school_id, employee_number, first_name, last_name, hire_date, profile_id) values
  ('eeee1111-0000-0000-0000-000000000098', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EMP-A098', 'Disposable', 'Terminate', '2024-01-01', '99999999-9999-9999-9999-999999999998');
