-- Fixtures for the Attendance regression suite
-- (20260817120000_attendance.sql + 20260817130000_attendance_hardening.sql).
-- Builds on 02_fixtures.sql (School A/B, teacher 11111111 School A, teacher
-- 33333333 School B, school_owner 22222222 School A), 03_academic_fixtures.sql
-- (academic year aaaa1111...0001 School A), 05_learner_fixtures.sql (class
-- cccc1111...0001 School A, learner 11110000...0001 enrolled in it via
-- enrollment ee110000...0001, learner 11110000...0002 NOT enrolled
-- anywhere — used as the "not actually in this class" test learner).
--
-- A distinct id prefix (a771e...) is used for the class_teacher_assignments
-- row created here so it can never collide with the ids
-- teaching_assignments.test.sql creates for the same class/teacher pair —
-- both run against the same database, and attendance.test.sql runs before
-- teaching_assignments.test.sql alphabetically, so this fixture (not that
-- test file) is what attendance's own tests can rely on existing.

-- A second School A teacher, deliberately NOT assigned to any class — the
-- "same school, but no class_teacher_assignments row at all" case, distinct
-- from teacher B1 (33333333), who additionally differs by tenant.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '12121212-1212-1212-1212-121212121212', 'authenticated', 'authenticated',
   'teacher.a2@schoola.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('12121212-1212-1212-1212-121212121212', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Teacher', 'A2', 'teacher.a2@schoola.test', 'teacher', 'active');

insert into public.class_teacher_assignments (id, school_id, academic_year_id, class_id, teacher_profile_id) values
  ('a771e000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111');
