-- Fixtures for the Parent Portal V1 regression suite
-- (20260825090000_parent_portal_v1.sql). Adds:
--
--   1. A guardian/parent in School B, for the cross-tenant isolation
--      assertion (School B's guardian must not see any of School A's
--      attendance/assessment/fee/reference data created by that suite's
--      own setup step).
--
--   2. An 'enrolled' learner_enrollments row for Learner A3
--      (11110000...0004, added by 12_guardian_management_fixtures.sql,
--      linked to guardian 55555555) in class cccc1111...0001. The suite's
--      attendance/assessment/fee test data is created against Learner A3,
--      NOT Learner A1 (11110000...0001) — by the time this suite runs,
--      learner_management.test.sql's own test 13 has already called
--      promote_learner() on Learner A1, marking their original enrollment
--      'promoted' and creating a new one with class_id NULL, which
--      attendance_records_validate_tenant() would then reject (it requires
--      an 'enrolled' row for the exact learner_id/class_id/academic_year_id
--      triple). A3's enrollment is exclusively owned by this suite, so it
--      is never touched by any other file.

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '18181818-1818-1818-1818-181818181818', 'authenticated', 'authenticated',
   'parent.b1@schoolb.test', jsonb_build_object('role', 'parent', 'tenant_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('18181818-1818-1818-1818-181818181818', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Parent', 'B1', 'parent.b1@schoolb.test', 'parent', 'active');

insert into public.learner_enrollments (id, school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date) values
  ('ee110000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000004',
   'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '2024-01-15');
