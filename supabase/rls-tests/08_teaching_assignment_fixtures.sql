-- Fixtures for the Teaching Assignment regression suite. Builds on
-- 02_fixtures.sql (School A/B, teacher 11111111 in School A, teacher
-- 33333333 in School B, school_owner 22222222 in School A), 03_academic_fixtures.sql
-- (academic year aaaa1111...0001 School A, bbbb1111...0001 School B), and
-- 05_learner_fixtures.sql (class cccc1111...0001 in School A, class
-- cccc2222...0001 in School B). Only a subject fixture is genuinely new.

insert into public.subjects (id, school_id, name) values
  ('facade00-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Mathematics'),
  ('facade00-0000-0000-0000-000000000002', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Mathematics');
