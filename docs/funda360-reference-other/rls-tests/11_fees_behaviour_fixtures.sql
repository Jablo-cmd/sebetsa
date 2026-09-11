-- Additional fixtures for the Fees and Behaviour regression suites. Builds
-- on 02_fixtures.sql (School A/B) and 03_academic_fixtures.sql (academic
-- year aaaa1111...0001 in School A, bbbb1111...0001 in School B) and
-- 05_learner_fixtures.sql (learner 11110000...0001 in School A,
-- 22220000...0001 in School B).
--
-- finance_manager/accountant (Fees) and vice_principal/department_head
-- (Behaviour) previously existed as roles with zero permissions beyond
-- school.view — these are their first fixtures.

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '17171717-1717-1717-1717-171717171717', 'authenticated', 'authenticated',
   'finance.a1@schoola.test', jsonb_build_object('role', 'finance_manager', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '13131313-1313-1313-1313-131313131313', 'authenticated', 'authenticated',
   'accountant.a1@schoola.test', jsonb_build_object('role', 'accountant', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '14141414-1414-1414-1414-141414141414', 'authenticated', 'authenticated',
   'viceprincipal.a1@schoola.test', jsonb_build_object('role', 'vice_principal', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '15151515-1515-1515-1515-151515151515', 'authenticated', 'authenticated',
   'depthead.a1@schoola.test', jsonb_build_object('role', 'department_head', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '16161616-1616-1616-1616-161616161616', 'authenticated', 'authenticated',
   'finance.b1@schoolb.test', jsonb_build_object('role', 'finance_manager', 'tenant_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('17171717-1717-1717-1717-171717171717', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Finance', 'A1', 'finance.a1@schoola.test', 'finance_manager', 'active'),
  ('13131313-1313-1313-1313-131313131313', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Accountant', 'A1', 'accountant.a1@schoola.test', 'accountant', 'active'),
  ('14141414-1414-1414-1414-141414141414', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'ViceP', 'A1', 'viceprincipal.a1@schoola.test', 'vice_principal', 'active'),
  ('15151515-1515-1515-1515-151515151515', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'DeptHead', 'A1', 'depthead.a1@schoola.test', 'department_head', 'active'),
  ('16161616-1616-1616-1616-161616161616', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Finance', 'B1', 'finance.b1@schoolb.test', 'finance_manager', 'active');
