-- Fixtures for the Guardian Invitations regression suite
-- (20260827090000_guardian_invitations.sql). Builds on 02_fixtures.sql
-- (School A/B, teacher 11111111, school_owner 22222222) and
-- 03_academic_fixtures.sql (guardian/parent 55555555 in School A, linked to
-- Learner A1 11110000...0001 as mother/primary via 05_learner_fixtures.sql;
-- school_owner 66666666 in School B) and 13_parent_portal_fixtures.sql
-- (guardian/parent 18181818 in School B).
--
-- Adds one dedicated guardian, "Nomsa Expired", solely for the
-- already-expired-invitation scenario. A real expiry can't be produced by
-- waiting inside a test run, so this fixture inserts an already-expired
-- 'pending' row directly (fixtures run as the connecting superuser, which
-- bypasses RLS — the same reason 02_fixtures.sql's own header comment gives
-- for why that's fine here but not inside a test's impersonated block).

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '9e9e9e9e-9e9e-9e9e-9e9e-9e9e9e9e9e9e', 'authenticated', 'authenticated',
   'expired.guardian.a1@schoola.test', jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('9e9e9e9e-9e9e-9e9e-9e9e-9e9e9e9e9e9e', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Nomsa', 'Expired', 'expired.guardian.a1@schoola.test', 'guardian', 'active');

insert into public.guardian_invitations (id, school_id, guardian_profile_id, status, invited_at, expires_at, created_by, updated_by) values
  ('9e9e0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '9e9e9e9e-9e9e-9e9e-9e9e-9e9e9e9e9e9e',
   'pending', now() - interval '5 days', now() - interval '2 days', '22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222');
