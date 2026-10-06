-- Additional fixtures for the Academic Structure regression suite. Builds
-- on 02_fixtures.sql's schools/users (School A/B, teacher/owner/platform
-- admin) — adds one more School A user with a role that gets NO academic
-- access at all, plus one academic year/grade per school to exercise
-- tenant isolation.

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '55555555-5555-5555-5555-555555555555', 'authenticated', 'authenticated',
   'parent.a1@schoola.test', jsonb_build_object('role', 'parent', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '66666666-6666-6666-6666-666666666666', 'authenticated', 'authenticated',
   'owner.b1@schoolb.test', jsonb_build_object('role', 'school_owner', 'tenant_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('55555555-5555-5555-5555-555555555555', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Parent', 'A1', 'parent.a1@schoola.test', 'parent', 'active'),
  ('66666666-6666-6666-6666-666666666666', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Owner', 'B1', 'owner.b1@schoolb.test', 'school_owner', 'active');

insert into public.academic_years (id, school_id, name, start_date, end_date, is_active) values
  ('aaaa1111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2026 Academic Year', '2026-01-15', '2026-12-05', true),
  ('bbbb1111-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '2026 Academic Year', '2026-01-15', '2026-12-05', true);

insert into public.grades (id, school_id, name, sort_order) values
  ('aaaa2222-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Grade 8', 8);
