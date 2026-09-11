-- Fixtures for the Guardian Management regression suite
-- (20260824090000_guardian_management.sql). Builds on 05_learner_fixtures.sql
-- (guardian/parent 55555555 already linked to Learner A1 11110000...0001 as
-- mother/primary; Learner A2 11110000...0002 also exists in School A) and
-- 02_fixtures.sql (School A owner 22222222, admissions_officer 10101010
-- from 05_learner_fixtures.sql, teacher 11111111).
--
-- Adds a second guardian (role=guardian, not role=parent — proving both
-- role values remain valid) for the multiple-guardians-per-learner case,
-- linked to Learner A1 as father/non-primary.
--
-- A dedicated third learner (Learner A3, 11110000...0004) is added here
-- rather than reusing Learner A2 (11110000...0002) for the
-- multiple-learners-per-guardian case: learner_management.test.sql's own
-- guardian-isolation test ("guardian can view own linked learner only")
-- asserts guardian 55555555 canNOT see Learner A2 specifically, so linking
-- 55555555 to A2 here would falsify that unrelated, pre-existing assertion
-- the moment this file's fixtures loaded — even though the RLS behavior
-- itself would be correct. A fixture only this suite owns avoids that
-- cross-file interference entirely.

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '59595959-5959-5959-5959-595959595959', 'authenticated', 'authenticated',
   'father.a1@schoola.test', jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, phone, role, status) values
  ('59595959-5959-5959-5959-595959595959', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sipho', 'Father', 'father.a1@schoola.test', '+27831112222', 'guardian', 'active');

insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
  ('1e110000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
   '59595959-5959-5959-5959-595959595959', 'father', false);

insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
  ('11110000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A0004', 'ADM-A0004', 'Naledi', 'A3', '2015-02-01', 'active', '2024-01-15');
