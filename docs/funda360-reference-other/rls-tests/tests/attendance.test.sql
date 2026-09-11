-- Regression suite for the Attendance domain (20260817120000_attendance.sql
-- + 20260817130000_attendance_hardening.sql). Uses fixtures from
-- 02_fixtures.sql (School A aaaaaaaa..., teacher A1 11111111, school_owner
-- A2 22222222, teacher B1 33333333 School B), 03_academic_fixtures.sql
-- (academic year aaaa1111...0001 School A, bbbb1111...0001 School B),
-- 04_employee_fixtures.sql (principal A1 77777777, hr_manager A1 88888888),
-- 05_learner_fixtures.sql (class cccc1111...0001 School A, learner
-- 11110000...0001 enrolled in it, learner 11110000...0002 NOT enrolled
-- anywhere), and 09_attendance_fixtures.sql (teacher A2 12121212 —
-- deliberately unassigned to any class — and the class_teacher_assignments
-- row a771e000...0001 assigning teacher A1 to class cccc1111...0001).

-- ---------------------------------------------------------------------------
-- 1. Cross-tenant FK spoofing: School B's owner cannot insert an attendance
-- record whose school_id is their own tenant but whose class_id belongs to
-- School A — the (now SECURITY DEFINER) validate_tenant trigger must reject
-- it even though it can now actually see the cross-tenant class row.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbb1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '22220000-0000-0000-0000-000000000001', '2026-08-17', 'present');
    call test_util.record('cross-tenant class_id reference is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cross-tenant class_id reference is rejected',
      v_error like '%class_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A teacher in the same school, with no class_teacher_assignments row at
-- all for this class, cannot record attendance for it.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001', '2026-08-17', 'present');
    call test_util.record('a teacher not assigned to the class cannot record attendance', false, 'INSERT succeeded unexpectedly');
  exception when others then
    call test_util.record('a teacher not assigned to the class cannot record attendance', true, 'INSERT correctly rejected');
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A teacher in a different school entirely cannot record attendance for
-- School A's class.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001', '2026-08-17', 'present');
    call test_util.record('a teacher from a different school cannot record attendance', false, 'INSERT succeeded unexpectedly');
  exception when others then
    call test_util.record('a teacher from a different school cannot record attendance', true, 'INSERT correctly rejected');
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. THE FIX (defect 1): a teacher actively assigned to the class can record
-- attendance for a learner genuinely enrolled in it. Before
-- 20260817130000_attendance_hardening.sql, this failed for every teacher —
-- the validate_tenant trigger's own internal `learners` lookup was itself
-- blocked by RLS under a teacher's session.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.attendance_records (id, school_id, academic_year_id, class_id, learner_id, attendance_date, status)
    values ('a771a000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
            '11110000-0000-0000-0000-000000000001', '2026-08-17', 'present');

  execute 'reset role';

  select count(*) into v_count from public.attendance_records where id = 'a771a000-0000-0000-0000-000000000001';
  call test_util.record('an assigned teacher can record attendance for their own class', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. THE FIX (defect 2): the same assigned teacher CANNOT record attendance
-- for a learner who is not actually enrolled in that class — even though
-- learner, class, and teacher all belong to the same school and the teacher
-- is genuinely assigned to the class. Learner 11110000...0002 has no
-- learner_enrollments row anywhere (05_learner_fixtures.sql).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000002', '2026-08-17', 'present');
    call test_util.record('cannot record attendance for a learner not enrolled in the class', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cannot record attendance for a learner not enrolled in the class',
      v_error like '%must be actively enrolled in class_id%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A principal (can_manage_academic — broad path) can record attendance
-- for the class even without holding any class_teacher_assignments row
-- themselves. Uses a different date from test 4 to avoid the unique index.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.attendance_records (id, school_id, academic_year_id, class_id, learner_id, attendance_date, status)
    values ('a771a000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
            '11110000-0000-0000-0000-000000000001', '2026-08-18', 'absent');

  execute 'reset role';

  select count(*) into v_count from public.attendance_records where id = 'a771a000-0000-0000-0000-000000000002';
  call test_util.record('a principal can record attendance for any class via the broad manage path', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Duplicate prevention: a second record for the same (learner, class,
-- date) as test 4 is rejected by the unique index.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000001', '2026-08-17', 'late');
    call test_util.record('duplicate (learner, class, date) is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('duplicate (learner, class, date) is rejected',
      v_error like '%duplicate key value violates unique constraint%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. THE FIX, roster visibility: the assigned teacher can now see the
-- enrolled learner's own `learners` row directly — before
-- 20260817130000_attendance_hardening.sql this returned zero rows (RLS
-- silently filtered it, no error), which is exactly what made
-- attendanceService.getClassRoster() appear as an empty class in the UI for
-- every teacher.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('an assigned teacher can see their enrolled learner''s record', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. THE FIX, roster visibility: the same teacher can see the
-- learner_enrollments row backing that roster.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_enrollments where id = 'ee110000-0000-0000-0000-000000000001';
  call test_util.record('an assigned teacher can see the class roster''s enrollment row', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Regression/scope check: the roster-visibility grant is narrowly
-- class-scoped, not a blanket teacher privilege — a teacher NOT assigned to
-- this class still cannot see the learner's record.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('roster visibility does not extend to an unassigned teacher', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Broad staff visibility: any teacher (can_view_academic, school-wide)
-- can see attendance recorded by someone else — the principal's test-6 row,
-- not just their own.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.attendance_records where id = 'a771a000-0000-0000-0000-000000000002';
  call test_util.record('a teacher can view attendance recorded by the principal', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Cross-tenant isolation: School B's teacher cannot see School A's
-- attendance records at all.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.attendance_records where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant attendance records remain invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Unauthorized role: hr_manager (no academic.view) cannot see attendance
-- at all, even within their own school.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.attendance_records where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('hr_manager cannot view attendance records', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. No DELETE policy exists — combined with FORCE ROW LEVEL SECURITY, hard
-- delete is impossible even for an authorized manager.
do $$
declare
  v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  delete from public.attendance_records where id = 'a771a000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;

  execute 'reset role';

  call test_util.record('hard delete is impossible even for a principal', v_deleted = 0, 'rows deleted: ' || v_deleted);
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Correction path: the assigned teacher can UPDATE (correct) their own
-- previously-recorded status.
do $$
declare
  v_updated int;
  v_status public.attendance_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.attendance_records set status = 'late' where id = 'a771a000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select status into v_status from public.attendance_records where id = 'a771a000-0000-0000-0000-000000000001';
  call test_util.record('an assigned teacher can correct a previously recorded status',
    v_updated = 1 and v_status = 'late', format('rows updated=%s status=%s', v_updated, v_status));
end;
$$;
