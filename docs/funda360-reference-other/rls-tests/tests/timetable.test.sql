-- Regression suite for Timetable Management (20260826090000_timetable.sql).
-- Uses 02_fixtures.sql (School A/B, teacher A1 11111111 School A, teacher
-- B1 33333333 School B, school_owner 22222222 School A, school_owner
-- 66666666 School B), 03_academic_fixtures.sql (academic year
-- aaaa1111...0001 School A, bbbb1111...0001 School B), 04_employee_fixtures.sql
-- (hr_manager 88888888 School A — profile.manage_any but no academic.manage),
-- 05_learner_fixtures.sql (class cccc1111...0001 School A, class
-- cccc2222...0001 School B), 08_teaching_assignment_fixtures.sql (subject
-- facade00...0001 School A, facade00...0002 School B),
-- 09_attendance_fixtures.sql (teacher A2 12121212 School A), and
-- 10_assessment_fixtures.sql (term 70000000...0001, School A, academic
-- year aaaa1111...0001). All timetable_entries rows used here are created
-- inline, not pre-seeded — this suite owns that data exclusively.

-- ---------------------------------------------------------------------------
-- 1. Unauthorized: a teacher (academic.view only, no academic.manage)
-- cannot create a timetable entry.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'monday', '08:00', '09:00');
    call test_util.record('a teacher cannot create a timetable entry', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot create a timetable entry', true, v_error);
  end;

  execute 'reset role';
end;
$$;

-- 2. hr_manager (profile.manage_any but no academic.manage) also cannot.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'monday', '08:00', '09:00');
    call test_util.record('hr_manager cannot create a timetable entry', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('hr_manager cannot create a timetable entry', true, v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Cross-tenant FK spoofing: School B's owner cannot create an entry
-- whose school_id is their own tenant but whose class_id belongs to School A.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbb1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000002',
              '33333333-3333-3333-3333-333333333333', 'monday', '08:00', '09:00');
    call test_util.record('cross-tenant class_id reference is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cross-tenant class_id reference is rejected',
      v_error like '%class_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- 4. Cross-tenant term_id spoofing: term_id from the wrong school is rejected.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, term_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbb1111-0000-0000-0000-000000000001',
              '70000000-0000-0000-0000-000000000001',
              'cccc2222-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000002',
              '33333333-3333-3333-3333-333333333333', 'monday', '08:00', '09:00');
    call test_util.record('cross-tenant term_id reference is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cross-tenant term_id reference is rejected',
      v_error like '%term_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Invalid time range: end_time before/equal to start_time is rejected by
-- the CHECK constraint.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'monday', '09:00', '08:00');
    call test_util.record('an invalid time range (end before start) is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an invalid time range (end before start) is rejected',
      v_error like '%timetable_entries_time_valid%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. THE FIX: an authorized manager (school_owner) can create a valid
-- timetable entry, with a room set.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
    values ('ab770000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
            'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
            'monday', '08:00', '09:00', 'Room 1');

  execute 'reset role';

  select count(*) into v_count from public.timetable_entries where id = 'ab770000-0000-0000-0000-000000000001';
  call test_util.record('authorized manager can create a timetable entry', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- 7. A non-overlapping entry for the SAME teacher/class/room on the same
-- day succeeds — proves the conflict check is time-range-aware, not a
-- blanket "one entry per teacher per day" rule.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('ab770000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
              'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
              'monday', '09:00', '10:00', 'Room 1');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('a back-to-back, non-overlapping entry for the same teacher/class/room succeeds', v_ok, coalesce(v_error, 'created'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. TEACHER CONFLICT: the same teacher cannot be double-booked at an
-- overlapping time, even for a different class/subject/room.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000002', 'facade00-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111', 'monday', '08:30', '09:30', 'Room 2');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('teacher double-booking at an overlapping time is rejected',
    v_ok and v_error like '%teacher already has an overlapping lesson%', coalesce(v_error, 'INSERT succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. CLASS CONFLICT: the same class cannot have two subjects scheduled at
-- an overlapping time, even with a different teacher/room.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
              '12121212-1212-1212-1212-121212121212', 'monday', '08:15', '08:45', 'Room 3');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('class double-booking at an overlapping time is rejected',
    v_ok and v_error like '%this class already has an overlapping lesson%', coalesce(v_error, 'INSERT succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. ROOM CONFLICT: the same room cannot host two lessons at an
-- overlapping time, even with a different teacher/class.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000002', 'facade00-0000-0000-0000-000000000001',
              '12121212-1212-1212-1212-121212121212', 'monday', '08:30', '09:00', 'Room 1');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('room double-booking at an overlapping time is rejected',
    v_ok and v_error like '%is already booked for an overlapping time%', coalesce(v_error, 'INSERT succeeded unexpectedly'));
end;
$$;

-- 11. No room conflict when the room differs — proves the check is scoped
-- to matching rooms, not a blanket same-time rejection.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('ab770000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000002',
              'facade00-0000-0000-0000-000000000001', '12121212-1212-1212-1212-121212121212',
              'monday', '08:30', '09:00', 'Room 2');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('a different room at the same time does not conflict', v_ok, coalesce(v_error, 'created'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Archived entries do not participate in conflict checks: archive
-- entry #1 (Monday 08:00-09:00, Room 1, teacher A1, class A1), then a new
-- entry at that exact same teacher/class/room/time succeeds.
do $$
declare
  v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.timetable_entries set active = false where id = 'ab770000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';
  call test_util.record('authorized manager can archive a timetable entry', v_updated = 1, 'rows updated: ' || v_updated);
end;
$$;

do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.timetable_entries (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id, day_of_week, start_time, end_time, room)
      values ('ab770000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
              'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
              'monday', '08:00', '09:00', 'Room 1');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('an archived entry no longer participates in conflict checks', v_ok, coalesce(v_error, 'created'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Unauthorized: a teacher cannot archive a timetable entry — RLS's
-- USING clause hides the row from the UPDATE, so it affects zero rows.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.timetable_entries set active = false where id = 'ab770000-0000-0000-0000-000000000002';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.timetable_entries where id = 'ab770000-0000-0000-0000-000000000002';
  call test_util.record('unauthorized user cannot archive a timetable entry',
    v_updated = 0 and v_active = true, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Teacher (can_view_academic, school-wide) can view the school's
-- timetable, not just their own lessons — same visibility model as the
-- rest of the academic structure.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.timetable_entries
    where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and id in (
        'ab770000-0000-0000-0000-000000000002', 'ab770000-0000-0000-0000-000000000003',
        'ab770000-0000-0000-0000-000000000004'
      );
  call test_util.record('teacher can view the school-wide timetable', v_count = 3, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- 15. Cross-tenant isolation: School B's teacher cannot see any of School
-- A's timetable.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.timetable_entries where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant timetable entries remain invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- 16. Cross-tenant isolation on the write side: School B's owner cannot
-- archive School A's timetable entry.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  update public.timetable_entries set active = false where id = 'ab770000-0000-0000-0000-000000000002';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.timetable_entries where id = 'ab770000-0000-0000-0000-000000000002';
  call test_util.record('cross-tenant manager cannot archive another school''s timetable entry',
    v_updated = 0 and v_active = true, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 17. No DELETE policy exists — combined with FORCE ROW LEVEL SECURITY,
-- hard delete is impossible even for an authorized manager.
do $$
declare
  v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  delete from public.timetable_entries where id = 'ab770000-0000-0000-0000-000000000002';
  get diagnostics v_deleted = row_count;

  execute 'reset role';
  call test_util.record('hard delete is impossible even for a manager', v_deleted = 0, 'rows deleted: ' || v_deleted);
end;
$$;
