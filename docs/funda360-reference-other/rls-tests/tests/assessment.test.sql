-- Regression suite for the Assessment domain (20260817140000_assessments.sql).
-- Uses fixtures from 02_fixtures.sql (School A aaaaaaaa..., teacher A1
-- 11111111, school_owner A2 22222222, teacher B1 33333333 School B),
-- 03_academic_fixtures.sql (academic year aaaa1111...0001 School A,
-- bbbb1111...0001 School B), 04_employee_fixtures.sql (principal A1
-- 77777777, hr_manager A1 88888888), 05_learner_fixtures.sql (class
-- cccc1111...0001 School A, class cccc2222...0001 School B, learner
-- 11110000...0001 enrolled in class cccc1111...0001, learner
-- 11110000...0002 NOT enrolled anywhere), 08_teaching_assignment_fixtures.sql
-- (subject facade00...0001 School A, facade00...0002 School B),
-- 09_attendance_fixtures.sql (teacher A2 12121212 — deliberately
-- unassigned to any class — and class_teacher_assignments row
-- a771e000...0001 assigning teacher A1 to class cccc1111...0001), and
-- 10_assessment_fixtures.sql (term 70000000...0001 School A,
-- 70000000...0002 School B).

-- ===========================================================================
-- ASSESSMENTS
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Cross-tenant FK spoofing: School B's owner cannot create an assessment
-- whose school_id is their own tenant but whose class_id belongs to School A.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessments (school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bbbb1111-0000-0000-0000-000000000001',
              '70000000-0000-0000-0000-000000000002', 'cccc1111-0000-0000-0000-000000000001',
              'facade00-0000-0000-0000-000000000002', 'Test 1', 'test', '2026-08-17', 50);
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
-- 2. An unassigned teacher (no class_teacher_assignments row at all) cannot
-- create an assessment for the class, even within the same school.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessments (school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              '70000000-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
              'facade00-0000-0000-0000-000000000001', 'Test 1', 'test', '2026-08-17', 50);
    call test_util.record('an unassigned teacher cannot create an assessment', false, 'INSERT succeeded unexpectedly');
  exception when others then
    call test_util.record('an unassigned teacher cannot create an assessment', true, 'INSERT correctly rejected');
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A teacher from a different school entirely cannot create an assessment
-- for School A's class.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessments (school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              '70000000-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
              'facade00-0000-0000-0000-000000000001', 'Test 1', 'test', '2026-08-17', 50);
    call test_util.record('a teacher from a different school cannot create an assessment', false, 'INSERT succeeded unexpectedly');
  exception when others then
    call test_util.record('a teacher from a different school cannot create an assessment', true, 'INSERT correctly rejected');
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. THE FIX: teacher A1, actively assigned to class A (a771e000...0001),
-- can create an assessment for it.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.assessments (id, school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
    values ('a55e5000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001',
            'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
            'Test 1', 'test', '2026-08-17', 50);

  execute 'reset role';

  select count(*) into v_count from public.assessments where id = 'a55e5000-0000-0000-0000-000000000001';
  call test_util.record('an assigned teacher can create an assessment for their own class', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Assessment uniqueness: a second assessment with the identical title,
-- for the same class + subject + term, is rejected while the first remains
-- active.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessments (school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001',
              '70000000-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001',
              'facade00-0000-0000-0000-000000000001', 'Test 1', 'test', '2026-08-18', 50);
    call test_util.record('a duplicate assessment (same class+subject+term+title) is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a duplicate assessment (same class+subject+term+title) is rejected',
      v_error like '%duplicate key value violates unique constraint%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. A principal (can_manage_academic — broad path) can create an
-- assessment for the class even without holding any class_teacher_assignments
-- row themselves. Uses a different title to avoid the uniqueness constraint.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.assessments (id, school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
    values ('a55e5000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001',
            'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
            'Assignment 1', 'assignment', '2026-08-18', 20);

  execute 'reset role';

  select count(*) into v_count from public.assessments where id = 'a55e5000-0000-0000-0000-000000000002';
  call test_util.record('a principal can create an assessment via the broad manage path', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Cross-tenant isolation: School B's teacher cannot see School A's
-- assessments.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.assessments where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant assessments remain invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Broad staff visibility: any teacher (can_view_academic, school-wide)
-- can see assessments across the whole school, not just their own class —
-- same visibility model as Teaching Assignments and Attendance. Counts
-- specifically the two ids this test file created (tests 4+6), not "every
-- row in the school", for the same stale-count reason
-- teaching_assignments.test.sql's own school-wide count was made robust to.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.assessments
    where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and id in ('a55e5000-0000-0000-0000-000000000001', 'a55e5000-0000-0000-0000-000000000002');
  call test_util.record('an unassigned teacher can still view school-wide assessments', v_count = 2, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Unauthorized role: hr_manager (no academic.view) cannot see assessments
-- at all, even within their own school.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.assessments where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('hr_manager cannot view assessments', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Archive: the assigned teacher can archive their own class's
-- assessment (active = false) — the product's own delete convention
-- (archive, not hard delete).
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.assessments set active = false where id = 'a55e5000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.assessments where id = 'a55e5000-0000-0000-0000-000000000001';
  call test_util.record('an assigned teacher can archive their own assessment',
    v_updated = 1 and v_active = false, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Reversibility: an archived assessment's title no longer blocks a new
-- one with the same natural key — proves the unique index only guards
-- active rows (same partial-index reasoning as Teaching Assignments).
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.assessments (id, school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
    values ('a55e5000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001',
            'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
            'Test 1', 'test', '2026-08-19', 50);

  execute 'reset role';

  select count(*) into v_count from public.assessments where id = 'a55e5000-0000-0000-0000-000000000003';
  call test_util.record('an archived assessment''s title no longer blocks a new one', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. No DELETE policy exists — combined with FORCE ROW LEVEL SECURITY, hard
-- delete is impossible even for a principal.
do $$
declare
  v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  delete from public.assessments where id = 'a55e5000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;

  execute 'reset role';

  call test_util.record('hard delete of an assessment is impossible even for a principal', v_deleted = 0, 'rows deleted: ' || v_deleted);
end;
$$;

-- ===========================================================================
-- ASSESSMENT RESULTS (marks)
-- ===========================================================================
-- Uses assessment a55e5000...0003 (School A, class A, active) from test 11.

-- ---------------------------------------------------------------------------
-- 13. THE FIX: the assigned teacher can record a mark for a learner
-- genuinely enrolled in the assessment's class.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.assessment_results (id, school_id, assessment_id, learner_id, mark)
    values ('a55e5000-0000-0000-0000-0000000000f1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'a55e5000-0000-0000-0000-000000000003', '11110000-0000-0000-0000-000000000001', 42);

  execute 'reset role';

  select count(*) into v_count from public.assessment_results where id = 'a55e5000-0000-0000-0000-0000000000f1';
  call test_util.record('an assigned teacher can record a mark for an enrolled learner', v_count = 1, 'rows created: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Learner integrity: the same teacher cannot record a mark for a
-- learner who is not enrolled in the assessment's class (learner
-- 11110000...0002 has no learner_enrollments row anywhere).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a55e5000-0000-0000-0000-000000000003',
              '11110000-0000-0000-0000-000000000002', 42);
    call test_util.record('cannot record a mark for a learner outside the assessment class', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cannot record a mark for a learner outside the assessment class',
      v_error like '%must be actively enrolled%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Mark validation: a negative mark is rejected by the CHECK constraint.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a55e5000-0000-0000-0000-000000000003',
              '11110000-0000-0000-0000-000000000001', -5);
    call test_util.record('a negative mark is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a negative mark is rejected',
      v_error like '%assessment_results_mark_non_negative%' or v_error like '%violates check constraint%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. Mark validation: a mark above the assessment's max_mark (50) is
-- rejected by the trigger.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a55e5000-0000-0000-0000-000000000003',
              '11110000-0000-0000-0000-000000000001', 999);
    call test_util.record('a mark above the maximum is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a mark above the maximum is rejected',
      v_error like '%cannot exceed the assessment''s maximum mark%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 17. Duplicate prevention: a second result for the same (assessment,
-- learner) as test 13 is rejected by the unique index.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a55e5000-0000-0000-0000-000000000003',
              '11110000-0000-0000-0000-000000000001', 30);
    call test_util.record('duplicate (assessment, learner) result is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('duplicate (assessment, learner) result is rejected',
      v_error like '%duplicate key value violates unique constraint%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 18. An unassigned teacher cannot record a mark against School A's
-- assessment either — same class-scope check as assessment creation.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a55e5000-0000-0000-0000-000000000003',
              '11110000-0000-0000-0000-000000000001', 30);
    call test_util.record('an unassigned teacher cannot record a mark', false, 'INSERT succeeded unexpectedly');
  exception when others then
    call test_util.record('an unassigned teacher cannot record a mark', true, 'INSERT correctly rejected');
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 19. Cross-tenant: School B's teacher cannot record a mark against School
-- A's assessment.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a55e5000-0000-0000-0000-000000000003',
              '11110000-0000-0000-0000-000000000001', 30);
    call test_util.record('a teacher from a different school cannot record a mark', false, 'INSERT succeeded unexpectedly');
  exception when others then
    call test_util.record('a teacher from a different school cannot record a mark', true, 'INSERT correctly rejected');
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 20. Correction path: the assigned teacher can UPDATE (correct) a
-- previously recorded mark.
do $$
declare
  v_updated int;
  v_mark int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.assessment_results set mark = 47 where id = 'a55e5000-0000-0000-0000-0000000000f1';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select mark into v_mark from public.assessment_results where id = 'a55e5000-0000-0000-0000-0000000000f1';
  call test_util.record('an assigned teacher can correct a previously recorded mark',
    v_updated = 1 and v_mark = 47, format('rows updated=%s mark=%s', v_updated, v_mark));
end;
$$;

-- ---------------------------------------------------------------------------
-- 21. No DELETE policy exists on assessment_results either — hard delete is
-- impossible even for a principal.
do $$
declare
  v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  delete from public.assessment_results where id = 'a55e5000-0000-0000-0000-0000000000f1';
  get diagnostics v_deleted = row_count;

  execute 'reset role';

  call test_util.record('hard delete of a result is impossible even for a principal', v_deleted = 0, 'rows deleted: ' || v_deleted);
end;
$$;

-- ---------------------------------------------------------------------------
-- 22. Cross-tenant isolation: School B's teacher cannot see School A's
-- results.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.assessment_results where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant assessment results remain invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 23. Broad staff visibility: an unassigned teacher (can_view_academic,
-- school-wide) can still view results recorded by another teacher — same
-- visibility model as the assessments themselves.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.assessment_results where id = 'a55e5000-0000-0000-0000-0000000000f1';
  call test_util.record('an unassigned teacher can still view results recorded by another teacher', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;
