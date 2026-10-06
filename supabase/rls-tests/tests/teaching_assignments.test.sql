-- Regression suite for the Teaching Assignment domain
-- (20260817090000_teaching_assignments.sql). Uses fixtures from
-- 02_fixtures.sql (School A/B, teacher 11111111 School A, teacher
-- 33333333 School B, school_owner 22222222 School A, school_owner
-- 66666666 School B), 03_academic_fixtures.sql (academic year
-- aaaa1111...0001 School A, bbbb1111...0001 School B), 04_employee_fixtures.sql
-- (hr_manager 88888888 School A — has profile.manage_any but no
-- academic.manage), 05_learner_fixtures.sql (class cccc1111...0001 School A,
-- class cccc2222...0001 School B), 08_teaching_assignment_fixtures.sql
-- (subject facade00-0000-0000-0000-000000000001 School A), and
-- 09_attendance_fixtures.sql (teacher A2 12121212 School A — deliberately
-- unassigned to any class there — and class_teacher_assignments row
-- a771e000...0001 assigning teacher A1 11111111 to class cccc1111...0001,
-- which is why tests 3 and 8 below use A2, not A1, for their own insert of
-- that exact natural key).

-- ---------------------------------------------------------------------------
-- 1. Unauthorized: hr_manager (no academic.manage) cannot create an
-- assignment.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.class_teacher_assignments (school_id, academic_year_id, class_id, teacher_profile_id)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');
    call test_util.record('hr_manager cannot create a teaching assignment', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('hr_manager cannot create a teaching assignment', true, v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Cross-tenant FK spoofing: School B's owner cannot create an assignment
-- whose school_id is their own tenant but whose class_id belongs to School A
-- — the validate_tenant trigger must reject it even though school_id alone
-- would satisfy can_manage_academic().
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.class_teacher_assignments (school_id, academic_year_id, class_id, teacher_profile_id)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbb1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333');
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
-- 3. THE FIX: School A's owner (can_manage_academic) can create a "class
-- teacher" assignment (subject_id null — responsible for the whole class).
-- Uses teacher A2 (12121212), not A1 (11111111): 09_attendance_fixtures.sql
-- (loaded before any test file runs, added after this test was originally
-- written) already occupies A1's exact natural key for this class/year with
-- subject_id null (row a771e000...0001), which would collide with the
-- unique index this insert would otherwise hit. A2 is documented there as
-- deliberately unassigned to any class, so assigning them here proves the
-- identical invariant without colliding with that fixture. Safe to leave A2
-- assigned afterward — this file runs last alphabetically, so no later test
-- file's "unassigned teacher" assumption about A2 is affected.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.class_teacher_assignments (id, school_id, academic_year_id, class_id, teacher_profile_id)
    values ('a5519000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
            '12121212-1212-1212-1212-121212121212');

  execute 'reset role';

  select count(*) into v_count from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000001';
  call test_util.record('authorized manager can create a class-teacher assignment', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Authorized manager can also create a "subject teacher" assignment
-- (subject_id set) for the same class, a different responsibility.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.class_teacher_assignments (id, school_id, academic_year_id, class_id, subject_id, teacher_profile_id)
    values ('a5519000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
            'facade00-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

  execute 'reset role';

  select count(*) into v_count from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000002';
  call test_util.record('authorized manager can create a subject-teacher assignment', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Duplicate prevention: a second identical active assignment (same year,
-- class, subject, teacher) is rejected by the partial unique index.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.class_teacher_assignments (school_id, academic_year_id, class_id, subject_id, teacher_profile_id)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
              '11111111-1111-1111-1111-111111111111');
    call test_util.record('duplicate active assignment is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('duplicate active assignment is rejected',
      v_error like '%duplicate key value violates unique constraint%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Teacher (academic.view, school-wide) can see assignments across the
-- whole school, not just their own — same visibility model as the rest of
-- the academic structure. Counts specifically the two ids this test file
-- itself created (tests 3+4), not "every row in the school" — 09_attendance
-- _fixtures.sql (loaded before any test file runs) also inserts a
-- class_teacher_assignments row for School A, and a blanket school-wide
-- count would go stale every time some other domain's fixtures add one,
-- same reasoning as scoping counts by id anywhere else in this suite.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.class_teacher_assignments
    where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and id in ('a5519000-0000-0000-0000-000000000001', 'a5519000-0000-0000-0000-000000000002');
  call test_util.record('teacher can view school-wide teaching assignments', v_count = 2, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Cross-tenant isolation: School B's teacher cannot see School A's
-- assignments.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.class_teacher_assignments where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant teaching assignments remain invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Unauthorized: the same teacher (no academic.manage) cannot archive an
-- assignment — RLS's USING clause hides the row from the UPDATE, so it
-- affects zero rows rather than raising. "The same teacher" as test 3, i.e.
-- A2 (12121212), who test 3 assigned to this row.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.class_teacher_assignments set active = false where id = 'a5519000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000001';
  call test_util.record('unauthorized user cannot archive an assignment',
    v_updated = 0 and v_active = true, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Authorized manager can archive an assignment.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.class_teacher_assignments set active = false where id = 'a5519000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000001';
  call test_util.record('authorized manager can archive an assignment',
    v_updated = 1 and v_active = false, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Regression: staff (can_view_academic) can still see the archived
-- assignment — visibility is not filtered by active, same as every other
-- archive-pattern table in this schema.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000001';
  call test_util.record('archived assignment remains visible to staff', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Reversibility: restoring an archived assignment now succeeds even
-- though an active duplicate would have been rejected (test 5) — proves the
-- partial unique index only guards active rows, not archived history.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.class_teacher_assignments set active = true where id = 'a5519000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000001';
  call test_util.record('restoring an archived assignment succeeds',
    v_updated = 1 and v_active = true, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. No DELETE policy exists — combined with FORCE ROW LEVEL SECURITY,
-- hard delete is impossible even for an authorized manager.
do $$
declare
  v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  delete from public.class_teacher_assignments where id = 'a5519000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;

  execute 'reset role';

  call test_util.record('hard delete is impossible even for a manager', v_deleted = 0, 'rows deleted: ' || v_deleted);
end;
$$;
