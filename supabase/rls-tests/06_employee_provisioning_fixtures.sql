-- Fixtures for provision_employee_login() regression tests. Builds on
-- 02_fixtures.sql (School A/B; principal 77777777 and hr_manager 88888888
-- added in 04_employee_fixtures.sql) and 04_employee_fixtures.sql
-- (departments dddd1111...; employees eeee1111...0001 [no work_email, no
-- login], eeee1111...0002 [linked to teacher profile 11111111]).

-- A provisionable employee: has a work_email, no linked login yet.
insert into public.employees (id, school_id, department_id, employee_number, first_name, last_name, hire_date, work_email) values
  ('eeee1111-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'dddd1111-0000-0000-0000-000000000001', 'EMP-A003', 'Provision', 'Ready', '2024-03-01', 'provision.ready@schoola.test');

-- A second provisionable employee whose work_email collides with an
-- existing auth.users email (the hr_manager fixture's own login), for the
-- email_taken rejection test.
insert into public.employees (id, school_id, employee_number, first_name, last_name, hire_date, work_email) values
  ('eeee1111-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EMP-A004', 'Email', 'Collision', '2024-03-01', 'hr.a1@schoola.test');
