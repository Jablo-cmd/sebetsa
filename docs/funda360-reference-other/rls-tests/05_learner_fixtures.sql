-- Additional fixtures for the Learner Management regression suite. Builds
-- on 02/03/04_fixtures.sql (School A/B, teacher 11111111, school_owner
-- 22222222, parent 55555555, school_owner 66666666 in School B, principal
-- 77777777, hr_manager 88888888, academic year aaaa1111...0001 and grade
-- aaaa2222...0001 both in School A).

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '10101010-1010-1010-1010-101010101010', 'authenticated', 'authenticated',
   'admissions.a1@schoola.test', jsonb_build_object('role', 'admissions_officer', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
  ('00000000-0000-0000-0000-000000000000', '20202020-2020-2020-2020-202020202020', 'authenticated', 'authenticated',
   'medical.a1@schoola.test', jsonb_build_object('role', 'medical_officer', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('10101010-1010-1010-1010-101010101010', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Admissions', 'A1', 'admissions.a1@schoola.test', 'admissions_officer', 'active'),
  ('20202020-2020-2020-2020-202020202020', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Medical', 'A1', 'medical.a1@schoola.test', 'medical_officer', 'active');

-- A class in School A's existing grade, for the grade/class consistency trigger test.
insert into public.classes (id, grade_id, school_id, name, capacity) values
  ('cccc1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Grade 8A', 30);

-- A second grade + class in School B, for cross-school FK tests.
insert into public.grades (id, school_id, name, sort_order) values
  ('cafe2222-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Grade 8', 8);
insert into public.classes (id, grade_id, school_id, name, capacity) values
  ('cccc2222-0000-0000-0000-000000000001', 'cafe2222-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Grade 8A', 30);

-- A second grade + class WITHIN School A, for testing grade/class
-- consistency specifically (same school, different grade) — distinct from
-- the cross-school case above.
insert into public.grades (id, school_id, name, sort_order) values
  ('aaaa2222-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Grade 9', 9);
insert into public.classes (id, grade_id, school_id, name, capacity) values
  ('cccc1111-0000-0000-0000-000000000002', 'aaaa2222-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Grade 9A', 30);

insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
  ('11110000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A0001', 'ADM-A0001', 'Lerato', 'A', '2014-03-01', 'active', '2024-01-15'),
  ('22220000-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'LRN-B0001', 'ADM-B0001', 'Sipho', 'B', '2014-05-01', 'active', '2024-01-15');

insert into public.learner_enrollments (id, school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date) values
  ('ee110000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '2024-01-15');

insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
  ('1e110000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
   '55555555-5555-5555-5555-555555555555', 'mother', true);

-- Disposable profile-linked learner, for learner-self-portal-access testing.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '30303030-3030-3030-3030-303030303030', 'authenticated', 'authenticated',
   'learner.a2@schoola.test', jsonb_build_object('role', 'learner', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('30303030-3030-3030-3030-303030303030', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Learner', 'A2', 'learner.a2@schoola.test', 'learner', 'active');

insert into public.learners (id, school_id, profile_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
  ('11110000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '30303030-3030-3030-3030-303030303030',
   'LRN-A0002', 'ADM-A0002', 'Thabo', 'A2', '2014-06-01', 'active', '2024-01-15');
