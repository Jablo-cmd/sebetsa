-- Fixtures for the Assessment regression suite
-- (20260817140000_assessments.sql). Builds on 02_fixtures.sql (School A
-- aaaaaaaa..., teacher A1 11111111, school_owner A2 22222222, teacher B1
-- 33333333 School B), 03_academic_fixtures.sql (academic year
-- aaaa1111...0001 School A, bbbb1111...0001 School B), 04_employee_fixtures.sql
-- (principal A1 77777777, hr_manager A1 88888888), 05_learner_fixtures.sql
-- (class cccc1111...0001 School A, class cccc2222...0001 School B, learner
-- 11110000...0001 enrolled in class cccc1111...0001, learner
-- 11110000...0002 NOT enrolled anywhere), 08_teaching_assignment_fixtures.sql
-- (subject facade00-0000-0000-0000-000000000001 School A), and
-- 09_attendance_fixtures.sql (teacher A2 12121212 — deliberately
-- unassigned to any class — and class_teacher_assignments row
-- a771e000...0001 assigning teacher A1 to class cccc1111...0001, reused
-- as-is here rather than duplicated, since it means exactly the same thing
-- for assessment's own class-scoping).
--
-- Only a term fixture is genuinely new here — no earlier sprint needed one.

insert into public.terms (id, academic_year_id, school_id, name, sequence, start_date, end_date) values
  ('70000000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Term 1', 1, '2026-01-15', '2026-04-01'),
  ('70000000-0000-0000-0000-000000000002', 'bbbb1111-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Term 1', 1, '2026-01-15', '2026-04-01');
