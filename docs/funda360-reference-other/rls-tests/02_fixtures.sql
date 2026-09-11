-- Fixture data for the RLS regression suite. Runs as the connecting
-- superuser, which bypasses RLS regardless of `force row level security`
-- (as intended — fixture setup isn't part of what's under test).

insert into public.schools (id, name, status) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'School A', 'active'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'School B', 'active');

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated',
   'teacher.a1@schoola.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
   'owner.a2@schoola.test', jsonb_build_object('role', 'school_owner', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated',
   'teacher.b1@schoolb.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')),
  ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated',
   'platform.admin@funda360.test', jsonb_build_object('role', 'platform_administrator'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Teacher', 'A1', 'teacher.a1@schoola.test', 'teacher', 'active'),
  ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Owner', 'A2', 'owner.a2@schoola.test', 'school_owner', 'active'),
  ('33333333-3333-3333-3333-333333333333', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Teacher', 'B1', 'teacher.b1@schoolb.test', 'teacher', 'active'),
  ('44444444-4444-4444-4444-444444444444', null, 'Platform', 'Admin', 'platform.admin@funda360.test', null, 'active');
