-- Regression suite for FND-TT-004 (20260829210000_timetable_substitutions.sql):
-- timetable_substitutions, its RLS (reusing can_view_academic()/
-- can_manage_academic() verbatim), the day-of-week/date consistency check,
-- and the genuine DELETE policy (unlike most tables in this schema).
--
-- Uses School A/B fixtures already established elsewhere: school_owner
-- 22222222, teacher 11111111 (view only), teacher A2 12121212
-- (09_attendance_fixtures.sql, also School A — used as the substitute),
-- class cccc1111...0001, subject facade00...0001, academic year
-- aaaa1111...0001. Creates its OWN dedicated timetable_entries row
-- (monday 06:00-06:45 — a time/day pair no other test file uses) so this
-- suite's outcome never depends on another file's own timetable fixture
-- data or execution order.
--
-- 2026-08-31 is a real, verified Monday (confirmed via `select trim(lower(
-- to_char('2026-08-31'::date, 'FMDay')))` = 'monday' during this
-- feature's own development); 2026-09-01 is the Tuesday immediately after
-- it, used for the day-mismatch rejection case.

-- ---------------------------------------------------------------------------
-- SETUP: a manager creates the recurring Monday lesson this suite covers.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time) values
    ('7f200000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
     'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
     'monday', '06:00', '06:45');
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 1. A manager assigns a substitute teacher for the correct Monday date —
-- succeeds.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.timetable_substitutions (id, school_id, timetable_entry_id, substitute_date, substitute_teacher_profile_id, reason) values
    ('7f300000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '7f200000-0000-0000-0000-000000000001',
     '2026-08-31', '12121212-1212-1212-1212-121212121212', 'Sick leave');
  execute 'reset role';

  select count(*) into v_count from public.timetable_substitutions where id = '7f300000-0000-0000-0000-000000000001';
  call test_util.record('a manager can assign a substitute for the correct day', v_count = 1, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. A teacher (view only) can see the substitution but cannot create one.
do $$
declare v_count int;
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.timetable_substitutions where id = '7f300000-0000-0000-0000-000000000001';

  begin
    insert into public.timetable_substitutions (school_id, timetable_entry_id, substitute_date, substitute_teacher_profile_id) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '7f200000-0000-0000-0000-000000000001', '2026-09-07', '12121212-1212-1212-1212-121212121212');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;

  execute 'reset role';

  call test_util.record('a viewer can see a substitution', v_count = 1, 'count=' || v_count);
  call test_util.record('a viewer without manage cannot create a substitution', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. A substitute_date that does not fall on the entry's own day_of_week
-- is rejected (Tuesday date for a Monday lesson).
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.timetable_substitutions (school_id, timetable_entry_id, substitute_date, substitute_teacher_profile_id) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '7f200000-0000-0000-0000-000000000001', '2026-09-01', '12121212-1212-1212-1212-121212121212');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a substitute_date on the wrong weekday is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. A cross-tenant substitute_teacher_profile_id is rejected.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.timetable_substitutions (school_id, timetable_entry_id, substitute_date, substitute_teacher_profile_id) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '7f200000-0000-0000-0000-000000000001', '2026-09-07', '33333333-3333-3333-3333-333333333333');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a cross-tenant substitute_teacher_profile_id is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. Tenant isolation: School B cannot see School A's substitution.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.timetable_substitutions where id = '7f300000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('School B cannot see School A''s substitution', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. A manager can cancel (hard-delete) a substitution — the genuine
-- exception to this schema's usual never-hard-delete pattern.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.timetable_substitutions where id = '7f300000-0000-0000-0000-000000000001';
  execute 'reset role';

  select count(*) into v_count from public.timetable_substitutions where id = '7f300000-0000-0000-0000-000000000001';
  call test_util.record('a manager can cancel a substitution outright', v_count = 0, 'count=' || v_count);
end $$;
