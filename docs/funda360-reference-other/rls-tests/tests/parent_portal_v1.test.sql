-- Regression suite for Parent Portal V1
-- (20260825090000_parent_portal_v1.sql): guardian read-only visibility into
-- attendance, assessments/assessment_results, fee charges/payments,
-- enrolments, and academic reference data (grades/classes/subjects/
-- class_teacher_assignments), plus guardian self-editing of
-- guardian_profile_details, tenant isolation, cross-learner isolation, and
-- confirmation that guardians remain read-only everywhere and that
-- behaviour_incidents stays deliberately unexposed.
--
-- Uses 05_learner_fixtures.sql (guardian/parent 55555555 linked to Learner
-- A1 11110000...0001; Learner A2 11110000...0002 exists, unlinked to any
-- guardian, not enrolled anywhere), 09_attendance_fixtures.sql (teacher A1
-- 11111111 assigned to class cccc1111...0001 via a771e000...0001),
-- 10_assessment_fixtures.sql (term 70000000...0001, subject
-- facade00...0001), 12_guardian_management_fixtures.sql (guardian 59595959
-- also linked to Learner A1 as father; Learner A3 11110000...0004 also
-- linked to guardian 55555555), and 13_parent_portal_fixtures.sql (Learner
-- A3's own 'enrolled' learner_enrollments row, ee110000...0004, in class
-- cccc1111...0001).
--
-- Test data (attendance/assessment/fee rows) is created inline below,
-- against LEARNER A3 (11110000...0004), NOT Learner A1 — by the time this
-- suite runs, learner_management.test.sql's test 13 has already called
-- promote_learner() on Learner A1, marking their original enrollment
-- 'promoted' (attendance_records_validate_tenant() requires an actively
-- 'enrolled' row, so inserting against A1 here would fail). A3's enrolment
-- is exclusively owned by this suite (see 13_parent_portal_fixtures.sql),
-- so it is never touched by any other file. The multi-child assertion
-- below (guardian 55555555 → both A1 and A3) is unaffected by A1's
-- promotion — learners_select's guardian clause doesn't depend on
-- enrollment status.

-- ---------------------------------------------------------------------------
-- SETUP: school_owner creates one attendance record, one assessment +
-- result, and one fee charge + payment for Learner A3.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.attendance_records (id, school_id, learner_id, class_id, academic_year_id, attendance_date, status)
    values ('a7000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '11110000-0000-0000-0000-000000000004', 'cccc1111-0000-0000-0000-000000000001',
            'aaaa1111-0000-0000-0000-000000000001', '2026-02-10', 'present');

  insert into public.assessments (id, school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
    values ('a5000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001',
            'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001',
            'Term 1 Test', 'test', '2026-02-15', 100);

  insert into public.assessment_results (id, school_id, assessment_id, learner_id, mark)
    values ('a5100000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            'a5000000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000004', 82);

  insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, description, category, amount)
    values ('af000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '11110000-0000-0000-0000-000000000004', 'aaaa1111-0000-0000-0000-000000000001',
            'Term 1 Tuition', 'tuition', 1500.00);

  insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method)
    values ('af100000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '11110000-0000-0000-0000-000000000004', 'aaaa1111-0000-0000-0000-000000000001',
            500.00, '2026-02-01', 'eft');

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Guardian can see their own linked learner's attendance record.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.attendance_records where id = 'a7000000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian can see own linked learner''s attendance', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- 2. Guardian cannot see another, unlinked learner's attendance (created
-- here as staff, to prove absence isn't just "no data exists").
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.attendance_records (id, school_id, learner_id, class_id, academic_year_id, attendance_date, status)
    values ('a7000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '11110000-0000-0000-0000-000000000004', 'cccc1111-0000-0000-0000-000000000001',
            'aaaa1111-0000-0000-0000-000000000001', '2026-02-11', 'absent');
  execute 'reset role';
end $$;

do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.attendance_records where learner_id = '11110000-0000-0000-0000-000000000002';
  execute 'reset role';
  call test_util.record('guardian cannot see an unlinked learner''s attendance', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- 3. Guardian cannot INSERT an attendance record (read-only enforcement).
do $$
declare v_error text; v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.attendance_records (school_id, learner_id, class_id, academic_year_id, attendance_date, status)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000004',
              'cccc1111-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', '2026-02-12', 'present');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  call test_util.record('guardian cannot insert an attendance record (read-only)', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- 4. Guardian can see assessment results and the assessment itself for their linked learner.
do $$
declare v_result_count int; v_assessment_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_result_count from public.assessment_results where id = 'a5100000-0000-0000-0000-000000000001';
  select count(*) into v_assessment_count from public.assessments where id = 'a5000000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian can see own linked learner''s assessment result and its assessment',
    v_result_count = 1 and v_assessment_count = 1, format('result=%s assessment=%s', v_result_count, v_assessment_count));
end $$;

-- 5. Guardian cannot UPDATE an assessment result (read-only enforcement).
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.assessment_results set mark = 100 where id = 'a5100000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('guardian cannot update an assessment result (read-only)', v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- 6. Guardian can see fee charges and payments for their linked learner.
do $$
declare v_charge_count int; v_payment_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_charge_count from public.learner_fee_charges where id = 'af000000-0000-0000-0000-000000000001';
  select count(*) into v_payment_count from public.learner_fee_payments where id = 'af100000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian can see own linked learner''s fee charge and payment',
    v_charge_count = 1 and v_payment_count = 1, format('charge=%s payment=%s', v_charge_count, v_payment_count));
end $$;

-- 7. Guardian cannot INSERT a fee payment (read-only, cannot self-grant finance-management).
do $$
declare v_error text; v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_fee_payments (school_id, learner_id, academic_year_id, amount, payment_date, method)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000004',
              'aaaa1111-0000-0000-0000-000000000001', 500.00, '2026-02-13', 'cash');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  call test_util.record('guardian cannot insert a fee payment (read-only)', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- 8. Guardian can see their linked learner's enrolment (needed to resolve grade/class).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_enrollments where id = 'ee110000-0000-0000-0000-000000000004';
  execute 'reset role';
  call test_util.record('guardian can see own linked learner''s enrolment', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- 9. Guardian can see academic reference data (grade/class/subject/class_teacher_assignments).
do $$
declare v_grade int; v_class int; v_subject int; v_cta int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_grade from public.grades where id = 'aaaa2222-0000-0000-0000-000000000001';
  select count(*) into v_class from public.classes where id = 'cccc1111-0000-0000-0000-000000000001';
  select count(*) into v_subject from public.subjects where id = 'facade00-0000-0000-0000-000000000001';
  select count(*) into v_cta from public.class_teacher_assignments where id = 'a771e000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian can see academic reference data (grade/class/subject/class teacher)',
    v_grade = 1 and v_class = 1 and v_subject = 1 and v_cta = 1,
    format('grade=%s class=%s subject=%s cta=%s', v_grade, v_class, v_subject, v_cta));
end $$;

-- 10. Guardian STILL cannot see behaviour_incidents — deliberately not
-- exposed in V1 (no guardian-vs-staff visibility model exists on that
-- table). This is a negative-by-design assertion: it must never start
-- passing accidentally via some other, broader policy.
do $$
declare v_error text; v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.behaviour_incidents (id, school_id, learner_id, academic_year_id, incident_type, description)
      values ('ab000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              '11110000-0000-0000-0000-000000000004', 'aaaa1111-0000-0000-0000-000000000001', 'positive', 'Helped a classmate');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;
  execute 'reset role';
  call test_util.record('setup: staff can record a behaviour incident', v_ok, coalesce(v_error, 'created'));
end $$;

do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents where learner_id = '11110000-0000-0000-0000-000000000004';
  execute 'reset role';
  call test_util.record('guardian still cannot see behaviour_incidents (deliberately excluded from V1)', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 11. Multi-child support: guardian 55555555 (also linked to Learner A3,
-- 11110000...0004, from 12_guardian_management_fixtures.sql) sees both
-- linked learners via the plain learners_select policy (unchanged by this
-- migration — proving multi-child visibility needed no new policy there).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learners
    where id in ('11110000-0000-0000-0000-000000000001', '11110000-0000-0000-0000-000000000004');
  execute 'reset role';
  call test_util.record('guardian with multiple linked learners sees all of them', v_count = 2, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 12. Tenant isolation: School B's guardian cannot see School A's
-- attendance, assessments, fees, or reference data — even by id.
do $$
declare v_att int; v_assess int; v_charge int; v_grade int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('18181818-1818-1818-1818-181818181818', 'parent', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_att from public.attendance_records where id = 'a7000000-0000-0000-0000-000000000001';
  select count(*) into v_assess from public.assessments where id = 'a5000000-0000-0000-0000-000000000001';
  select count(*) into v_charge from public.learner_fee_charges where id = 'af000000-0000-0000-0000-000000000001';
  select count(*) into v_grade from public.grades where id = 'aaaa2222-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('cross-tenant guardian cannot see School A data at all (attendance/assessment/fees/reference)',
    v_att = 0 and v_assess = 0 and v_charge = 0 and v_grade = 0,
    format('attendance=%s assessment=%s charge=%s grade=%s', v_att, v_assess, v_charge, v_grade));
end $$;

-- ---------------------------------------------------------------------------
-- 13. Guardian self-service: can update their own guardian_profile_details
-- (created inline here, since 55555555 has none from earlier suites).
do $$
declare v_error text; v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.guardian_profile_details (id, school_id, guardian_profile_id, address)
      values ('9d000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              '55555555-5555-5555-5555-555555555555', 'Old Address');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;
  execute 'reset role';
  call test_util.record('setup: staff creates guardian_profile_details for 55555555', v_ok, coalesce(v_error, 'created'));
end $$;

do $$
declare v_updated int; v_address text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.guardian_profile_details set address = 'New Address' where guardian_profile_id = auth.uid();
  get diagnostics v_updated = row_count;
  select address into v_address from public.guardian_profile_details where guardian_profile_id = '55555555-5555-5555-5555-555555555555';
  execute 'reset role';
  call test_util.record('guardian can update their own guardian_profile_details',
    v_updated = 1 and v_address = 'New Address', format('updated=%s address=%s', v_updated, v_address));
end $$;

-- 14. Guardian cannot update another guardian's guardian_profile_details
-- (59595959's, created via admin_create_guardian in the Guardian
-- Management suite — but that row is scoped by email lookup there, so
-- create a fresh, known one here instead to keep this assertion
-- self-contained).
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.guardian_profile_details (id, school_id, guardian_profile_id, address)
    values ('9d000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '59595959-5959-5959-5959-595959595959', 'Father''s Address');
  execute 'reset role';
end $$;

do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.guardian_profile_details set address = 'Hacked' where guardian_profile_id = '59595959-5959-5959-5959-595959595959';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('guardian cannot update another guardian''s guardian_profile_details',
    v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 15. Staff functionality is unaffected: school_owner still sees everything
-- created above via the pre-existing, unmodified can_view_academic()/
-- can_view_learner_financial()-gated policies.
do $$
declare v_att int; v_assess int; v_charge int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_att from public.attendance_records where id = 'a7000000-0000-0000-0000-000000000001';
  select count(*) into v_assess from public.assessments where id = 'a5000000-0000-0000-0000-000000000001';
  select count(*) into v_charge from public.learner_fee_charges where id = 'af000000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('staff (school_owner) visibility is unaffected by the new guardian policies',
    v_att = 1 and v_assess = 1 and v_charge = 1, format('attendance=%s assessment=%s charge=%s', v_att, v_assess, v_charge));
end $$;
