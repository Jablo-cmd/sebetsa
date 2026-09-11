-- Regression suite for FND-ATT-002 (20260829130000_attendance_alerts.sql):
-- the attendance_records_check_alert() trigger that notifies a learner's
-- guardians on a 3-consecutive-absence streak.
--
-- Creates its own dedicated learner AND dedicated guardian (never reused/
-- mutated by any other test file — the same isolation notifications.test
-- .sql already established for its own guardian fixture) rather than
-- reusing Learner A1 / guardian 55555555. Two independent reasons:
--  1. A1 already accumulates attendance_records from attendance.test.sql /
--     parent_portal_v1.test.sql dated later than this suite's own test
--     dates, and the trigger walks backward from the LATEST record for a
--     learner regardless of which test file wrote it — a shared learner
--     would make this suite's outcome depend on other files' dates and
--     test-execution order.
--  2. Reusing guardian 55555555 was tried first and broke two unrelated,
--     exact-count assertions elsewhere (guardian_management.test.sql's
--     "guardian now has two active learner links" and
--     guardian_invitations.test.sql's "only their own linked child") —
--     adding a 3rd linked child to a guardian other tests assert an exact
--     link-count for is exactly the kind of shared-fixture mutation this
--     suite's own isolation should avoid, not something to chase through
--     every other file that touches that guardian.
-- Learners enrolled in the existing class cccc1111...0001 / academic year
-- aaaa1111...0001 (School A — 05_learner_fixtures.sql /
-- 03_academic_fixtures.sql). Uses teacher 11111111 (assigned to class
-- cccc1111...0001 via a771e000...0001 — 09_attendance_fixtures.sql) to
-- record attendance. Adds 2 new School A learners — bumped
-- learner_management.test.sql's own hardcoded School A headcount assertion
-- accordingly, matching the exact precedent already set there for Learner
-- A3's own addition.

do $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', '5a110000-5a11-5a11-5a11-5a110000aa01',
     'authenticated', 'authenticated', 'attendance-alert-guardian@schoola.test',
     jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('5a110000-5a11-5a11-5a11-5a110000aa01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'AttAlert', 'Guardian', 'attendance-alert-guardian@schoola.test', 'guardian', 'active');

  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000aa01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-ATT01', 'ADM-A-ATT01', 'Attendance', 'AlertTest', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_enrollments (id, school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date) values
    ('ee110000-0000-0000-0000-00000000aa01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000aa01',
     'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '2024-01-15');
  insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('1e110000-0000-0000-0000-00000000aa01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000aa01',
     '5a110000-5a11-5a11-5a11-5a110000aa01', 'mother', true);
end $$;

-- ---------------------------------------------------------------------------
-- 1. Two absences in a row: no notification yet (streak hasn't reached 3).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-02', 'absent'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-03', 'absent');
  execute 'reset role';

  select count(*) into v_count from public.notifications where type = 'attendance_alert' and related_entity_id in (
    select id from public.attendance_records where learner_id = '11110000-0000-0000-0000-00000000aa01'
  );
  call test_util.record('two consecutive absences do not yet trigger a notification', v_count = 0, 'rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. A third consecutive absence triggers exactly one notification for the
-- guardian, with the right type/title/link_path.
do $$
declare v_count int;
declare v_link text;
declare v_title text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-04', 'absent');
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('5a110000-5a11-5a11-5a11-5a110000aa01', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.notifications where recipient_profile_id = '5a110000-5a11-5a11-5a11-5a110000aa01' and type = 'attendance_alert'
    and related_entity_id in (select id from public.attendance_records where learner_id = '11110000-0000-0000-0000-00000000aa01');
  select link_path, title into v_link, v_title from public.notifications
    where recipient_profile_id = '5a110000-5a11-5a11-5a11-5a110000aa01' and type = 'attendance_alert'
      and related_entity_id in (select id from public.attendance_records where learner_id = '11110000-0000-0000-0000-00000000aa01');
  execute 'reset role';

  call test_util.record('the 3rd consecutive absence creates exactly one notification', v_count = 1, 'rows: ' || v_count);
  call test_util.record('the notification links to the child''s Parent Portal profile', v_link = '/parent/children/11110000-0000-0000-0000-00000000aa01', 'link_path=' || coalesce(v_link, '(null)'));
  call test_util.record('the notification has the expected title', v_title = 'Attendance alert', 'title=' || coalesce(v_title, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. A 4th consecutive absence does NOT create a second notification — the
-- streak already fired once.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-05', 'absent');
  execute 'reset role';

  select count(*) into v_count from public.notifications where type = 'attendance_alert' and related_entity_id in (
    select id from public.attendance_records where learner_id = '11110000-0000-0000-0000-00000000aa01'
  );
  call test_util.record('a 4th consecutive absence does not create a duplicate notification', v_count = 1, 'rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. The streak breaks (a present day), then reaches 3 again in a SINGLE
-- multi-row INSERT — this both proves a new streak fires again AND that
-- batched inserts within one statement still only fire once, not once per
-- row (see the migration's own comment on why a naive position-based guard
-- would double/triple-fire here).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-06', 'present'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-09', 'absent'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-10', 'absent'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa01', '2026-03-11', 'absent');
  execute 'reset role';

  select count(*) into v_count from public.notifications where type = 'attendance_alert' and related_entity_id in (
    select id from public.attendance_records where learner_id = '11110000-0000-0000-0000-00000000aa01'
  );
  call test_util.record('a new 3-consecutive-absence streak after a break fires exactly one more notification, even inserted as a single multi-row batch', v_count = 2, 'rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. A second dedicated learner with no absences at all (a mix of
-- present/late) never generates a notification.
do $$
declare v_count int;
begin
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000aa02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-ATT02', 'ADM-A-ATT02', 'Attendance', 'NoAlertTest', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_enrollments (id, school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date) values
    ('ee110000-0000-0000-0000-00000000aa02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000aa02',
     'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '2024-01-15');

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa02', '2026-03-02', 'present'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-00000000aa02', '2026-03-03', 'late');
  execute 'reset role';

  select count(*) into v_count from public.notifications where type = 'attendance_alert' and related_entity_id in (
    select id from public.attendance_records where learner_id = '11110000-0000-0000-0000-00000000aa02'
  );
  call test_util.record('present/late days never trigger an attendance alert', v_count = 0, 'rows: ' || v_count);
end $$;
