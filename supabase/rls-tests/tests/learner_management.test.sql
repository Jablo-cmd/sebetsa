-- Regression suite for Sprint 2 Milestone 3 Phase 1 (Learner Management
-- database layer): view/manage role split (including the Teacher
-- dependency-gap block), guardian/self self-access, tenant isolation,
-- grade/class consistency, tenant-match triggers, primary-guardian
-- uniqueness, status transitions (valid + invalid), promote_learner,
-- the separately-gated medical table, no-hard-delete, and audit columns.

-- ---------------------------------------------------------------------------
-- 1. School owner (manage) can view the learner directory for their own school.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('school owner can view own school learner directory', v_count = 2, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. A teacher with no class relationship at all is blocked from the
-- learner directory entirely. Uses teacher A2 (12121212, added by
-- 09_attendance_fixtures.sql), deliberately unassigned to any class —
-- NOT teacher A1 (11111111), who 09_attendance_fixtures.sql assigns to
-- class cccc1111...0001, and who is therefore now expected to see exactly
-- that class's one enrolled learner (see attendance.test.sql tests 8-10,
-- which prove that narrow exception exists and goes no further than this).
-- Originally this dependency gap had no exception at all (see the sprint
-- this comment used to cite); Teaching Assignments + Attendance later
-- added a deliberate, narrowly class-scoped one, so this test was updated
-- to keep verifying the case it actually means to: zero relationship,
-- zero visibility.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('a teacher with no class relationship has no learner directory access', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Admissions officer (manage) can create a learner.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('10101010-1010-1010-1010-101010101010', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, admission_date)
      values ('11110000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A0003', 'ADM-A0003', 'New', 'Applicant', '2015-01-01', '2026-01-15');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('admissions officer can create a learner', v_ok, coalesce(v_error, 'created'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Tenant isolation: School B owner cannot see School A's learners.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant learners are invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Guardian (linked via learner_guardians, no learner.view) can see own
-- linked learner's record, and nobody else's.
do $$
declare
  v_own_count int;
  v_other_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_own_count from public.learners where id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_other_count from public.learners where id = '11110000-0000-0000-0000-000000000002';

  call test_util.record('guardian can view own linked learner only',
    v_own_count = 1 and v_other_count = 0, 'own=' || v_own_count || ' other=' || v_other_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Learner self-access via profile_id, without learner.view.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('30303030-3030-3030-3030-303030303030', 'learner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where id = '11110000-0000-0000-0000-000000000002';
  call test_util.record('learner can view own linked record via profile_id', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grade/class consistency: class_id must belong to the enrollment's own grade_id.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000002',
              'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001',
              'cccc1111-0000-0000-0000-000000000002', '2026-01-15');
    call test_util.record('enrollment class_id must belong to its own grade_id', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('enrollment class_id must belong to its own grade_id',
      v_error like '%class_id must belong to the same grade%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Tenant-match trigger: enrollment grade_id must belong to the same school.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, enrollment_date)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000002',
              'aaaa1111-0000-0000-0000-000000000001', 'cafe2222-0000-0000-0000-000000000001', '2026-01-15');
    call test_util.record('enrollment grade_id must belong to the same school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('enrollment grade_id must belong to the same school',
      v_error like '%grade_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Guardian tenant-match: cannot link a School B profile as a School A learner's guardian.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_guardians (school_id, learner_id, guardian_profile_id, relationship_type)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000002',
              '66666666-6666-6666-6666-666666666666', 'other');
    call test_util.record('guardian_profile_id must belong to the same school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('guardian_profile_id must belong to the same school',
      v_error like '%guardian_profile_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Only one primary guardian per learner (partial unique index).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_guardians (school_id, learner_id, guardian_profile_id, relationship_type, is_primary)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
              '10101010-1010-1010-1010-101010101010', 'other', true);
    call test_util.record('only one primary guardian per learner', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('only one primary guardian per learner',
      v_error like '%duplicate key%' or v_error like '%learner_guardians_one_primary_per_learner%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Valid status transition (active -> suspended) via change_learner_status.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_status public.learner_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.change_learner_status('11110000-0000-0000-0000-000000000002', 'suspended', 'disciplinary review');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select status into v_status from public.learners where id = '11110000-0000-0000-0000-000000000002';
  call test_util.record('valid status transition succeeds via change_learner_status',
    v_ok and v_status = 'suspended', coalesce(v_error, 'status now: ' || v_status::text));
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Invalid status transition rejected (prospective -> graduated, skipping the chain).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.change_learner_status('11110000-0000-0000-0000-000000000003', 'graduated', null);
    call test_util.record('invalid status transition is rejected', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('invalid status transition is rejected',
      v_error like '%invalid learner status transition%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. promote_learner atomically creates a new enrollment and marks the prior one promoted.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_prior_status public.learner_enrollment_status;
  v_new_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.promote_learner('11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000002', 'aaaa2222-0000-0000-0000-000000000001', null);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select enrollment_status into v_prior_status from public.learner_enrollments where id = 'ee110000-0000-0000-0000-000000000001';
  select count(*) into v_new_count from public.learner_enrollments
    where learner_id = '11110000-0000-0000-0000-000000000001' and academic_year_id = 'aaaa1111-0000-0000-0000-000000000002';

  call test_util.record('promote_learner atomically promotes and creates the new enrollment',
    v_ok and v_prior_status = 'promoted' and v_new_count = 1,
    coalesce(v_error, format('prior=%s new_rows=%s', v_prior_status, v_new_count)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Medical information is separately gated: admissions officer (has
-- learner.view/manage) cannot see medical info; medical officer can.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('10101010-1010-1010-1010-101010101010', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_medical_information (school_id, learner_id, allergies)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'peanuts');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('learner.view/manage does not grant medical access', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end;
$$;

do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('20202020-2020-2020-2020-202020202020', 'medical_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_medical_information (school_id, learner_id, allergies)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'peanuts');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('medical officer can manage medical information', v_ok, coalesce(v_error, 'created'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Guardian can view own child's medical information without learner.view_medical.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_medical_information where learner_id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('guardian can view own child''s medical information', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. Learners cannot be hard-deleted (no DELETE policy).
do $$
declare
  v_count_before int;
  v_count_after int;
begin
  select count(*) into v_count_before from public.learners where id = '11110000-0000-0000-0000-000000000001';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.learners where id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';

  select count(*) into v_count_after from public.learners where id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('learners cannot be hard-deleted (no DELETE policy)',
    v_count_before = 1 and v_count_after = 1, format('before=%s after=%s', v_count_before, v_count_after));
end;
$$;

-- ---------------------------------------------------------------------------
-- 17. created_by/updated_by are populated from the acting user.
do $$
declare
  v_created_by uuid;
begin
  select created_by into v_created_by from public.learners where id = '11110000-0000-0000-0000-000000000003';
  call test_util.record('created_by is populated from the acting user',
    v_created_by = '10101010-1010-1010-1010-101010101010', 'created_by=' || coalesce(v_created_by::text, 'null'));
end;
$$;
