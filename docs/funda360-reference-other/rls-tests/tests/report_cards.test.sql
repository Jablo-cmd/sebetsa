-- Regression suite for 20260904100000_report_cards.sql.
--
-- Reuses only stable fixtures: School A aaaaaaaa, year aaaa1111...0001,
-- term 70000000...0001 (10_assessment_fixtures), grade aaaa2222...0001,
-- class cccc1111...0001, subject facade00...0001 (Mathematics, School A),
-- class_teacher_assignments a771e000...0001 (teacher A1 11111111 -> that
-- class, subject_id null = class teacher), teacher A2 12121212
-- (unassigned), school_owner A2 22222222, principal A1 77777777, School B
-- teacher 33333333.
--
-- Creates its OWN learners / guardian / department_head / grading scale /
-- templates / assessments / attendance / behaviour — the isolation lesson
-- from fee_overdue_reminders.test.sql: the shared learner 11110000...0001
-- gets promoted/withdrawn by learner_management.test.sql (which runs
-- earlier), so its enrolment state cannot be relied on here.

do $$
begin
  -- Dedicated learners in class cccc1111 for year aaaa1111.
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('bc110000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-RC-1', 'ADM-RC-1', 'Rc', 'LearnerOne', '2013-03-01', 'active', '2024-01-15');
  insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bc110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '2026-01-15');

  -- A guardian for learner one.
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', 'bc110000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'rc.guardian@schoola.test',
     jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('bc110000-0000-0000-0000-0000000000a2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rc', 'Guardian', 'rc.guardian@schoola.test', 'guardian', 'active');
  insert into public.learner_guardians (school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bc110000-0000-0000-0000-000000000001', 'bc110000-0000-0000-0000-0000000000a2', 'mother', true);

  -- A profile-linked learner (learner-self access).
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', 'bc110000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'rc.learner@schoola.test',
     jsonb_build_object('role', 'learner', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('bc110000-0000-0000-0000-0000000000a3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rc', 'SelfLearner', 'rc.learner@schoola.test', 'learner', 'active');
  insert into public.learners (id, school_id, profile_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('bc110000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bc110000-0000-0000-0000-0000000000a3', 'LRN-RC-2', 'ADM-RC-2', 'Rc', 'LearnerTwo', '2013-06-01', 'active', '2024-01-15');
  insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bc110000-0000-0000-0000-000000000002', 'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', '2026-01-15');

  -- A department_head (HOD-review path).
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', 'd0d0d0d0-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'rc.hod@schoola.test',
     jsonb_build_object('role', 'department_head', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('d0d0d0d0-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rc', 'Hod', 'rc.hod@schoola.test', 'department_head', 'active');

  -- Grading scale + bands.
  insert into public.grading_scales (id, school_id, name) values
    ('4c1d0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'RC Test Scale');
  insert into public.grading_scale_bands (grading_scale_id, school_id, code, label, min_percentage, max_percentage) values
    ('4c1d0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'A', 'Outstanding', 80, 100),
    ('4c1d0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'B', 'Good',        60, 79),
    ('4c1d0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'C', 'Adequate',    40, 59),
    ('4c1d0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'D', 'Elementary',   0, 39);

  insert into public.report_card_templates (id, school_id, name, grading_scale_id, requires_hod_review) values
    ('4c1d0000-0000-0000-0000-0000000ab001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'RC Test Standard', '4c1d0000-0000-0000-0000-000000000001', false),
    ('4c1d0000-0000-0000-0000-0000000ab002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'RC Test HOD',      '4c1d0000-0000-0000-0000-000000000001', true);

  -- Maths: test 40/50 (w1) + exam 60/100 (w3) -> weighted mean of
  -- percentages = (80*1 + 60*3) / 4 = 65. For BOTH dedicated learners.
  insert into public.assessments (id, school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark, weight) values
    ('4c1d0000-0000-0000-0000-00000a55e001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001', 'RC Maths Test', 'test', '2026-02-10', 50, 1),
    ('4c1d0000-0000-0000-0000-00000a55e002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001', 'RC Maths Exam', 'examination', '2026-03-01', 100, 3);
  insert into public.assessment_results (school_id, assessment_id, learner_id, mark) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '4c1d0000-0000-0000-0000-00000a55e001', 'bc110000-0000-0000-0000-000000000001', 40),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '4c1d0000-0000-0000-0000-00000a55e002', 'bc110000-0000-0000-0000-000000000001', 60),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '4c1d0000-0000-0000-0000-00000a55e001', 'bc110000-0000-0000-0000-000000000002', 40),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '4c1d0000-0000-0000-0000-00000a55e002', 'bc110000-0000-0000-0000-000000000002', 60);

  -- Attendance for learner one in the term window: 2 present, 1 absent, 1 late.
  insert into public.attendance_records (school_id, academic_year_id, class_id, learner_id, attendance_date, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', 'bc110000-0000-0000-0000-000000000001', '2026-02-02', 'present'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', 'bc110000-0000-0000-0000-000000000001', '2026-02-03', 'present'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', 'bc110000-0000-0000-0000-000000000001', '2026-02-04', 'absent'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', 'cccc1111-0000-0000-0000-000000000001', 'bc110000-0000-0000-0000-000000000001', '2026-02-05', 'late');

  -- Behaviour for learner one in the term window: 1 positive, 1 negative.
  insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, description, occurred_at) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bc110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'positive', 'Great effort', '2026-02-10T09:00:00Z'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bc110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'negative', 'Disruptive', '2026-02-12T09:00:00Z');
end $$;

-- ---------------------------------------------------------------------------
-- 1. The class teacher generates a card; aggregation is correct.
do $$
declare v_rc public.report_cards; v_subj public.report_card_subjects;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select * into v_rc from public.generate_report_card(
    'bc110000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', '4c1d0000-0000-0000-0000-0000000ab001');

  call test_util.record('the class teacher can generate a report card', v_rc.status = 'draft', v_rc.status::text);
  call test_util.record('overall average is the assessment.weight-weighted mean (65.00)', v_rc.overall_average_percentage = 65.00, 'got: ' || coalesce(v_rc.overall_average_percentage::text, 'null'));
  call test_util.record('overall achievement resolves to band B (60-79)', v_rc.overall_achievement_code = 'B', 'got: ' || coalesce(v_rc.overall_achievement_code, 'null'));
  call test_util.record('attendance snapshot: 2 present / 1 absent / 1 late / 4 days',
    v_rc.attendance_present = 2 and v_rc.attendance_absent = 1 and v_rc.attendance_late = 1 and v_rc.attendance_total_days = 4,
    format('p%s a%s l%s t%s', v_rc.attendance_present, v_rc.attendance_absent, v_rc.attendance_late, v_rc.attendance_total_days));
  call test_util.record('conduct snapshot: 1 positive / 1 negative',
    v_rc.conduct_positive_count = 1 and v_rc.conduct_negative_count = 1,
    format('pos%s neg%s', v_rc.conduct_positive_count, v_rc.conduct_negative_count));

  select * into v_subj from public.report_card_subjects where report_card_id = v_rc.id and subject_id = 'facade00-0000-0000-0000-000000000001';
  call test_util.record('the Mathematics subject row aggregates to 65.00 over 2 assessments',
    v_subj.average_percentage = 65.00 and v_subj.assessment_count = 2,
    format('avg %s count %s', v_subj.average_percentage, v_subj.assessment_count));

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. An unassigned teacher, and School B, cannot generate for this learner.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.generate_report_card('bc110000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000001', '4c1d0000-0000-0000-0000-0000000ab002');
    call test_util.record('an unassigned teacher cannot generate a report card', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an unassigned teacher cannot generate a report card', true, v_error);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.generate_report_card('bc110000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', '4c1d0000-0000-0000-0000-0000000ab001');
    call test_util.record('School B cannot generate a report card for a School A learner', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B cannot generate a report card for a School A learner', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Generating a second live card for the same learner/term/template fails.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.generate_report_card('bc110000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', '4c1d0000-0000-0000-0000-0000000ab001');
    call test_util.record('a duplicate live report card is rejected', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a duplicate live report card is rejected', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Workflow: submit -> (teacher can't approve) -> principal approves ->
-- locked (recalculate + comment edits now reject) -> publish.
do $$
declare v_rc_id uuid; v_error text; v_status public.report_card_status; v_locked boolean;
begin
  select id into v_rc_id from public.report_cards
    where learner_id = 'bc110000-0000-0000-0000-000000000001' and template_id = '4c1d0000-0000-0000-0000-0000000ab001' and status = 'draft';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  perform public.set_report_card_subject_comment(
    (select id from public.report_card_subjects where report_card_id = v_rc_id limit 1), 'Solid progress.');
  perform public.set_report_card_comment(v_rc_id, 'class_teacher_comment', 'A committed term.');

  select status into v_status from public.submit_report_card(v_rc_id);
  call test_util.record('submit moves the card to teacher_review', v_status = 'teacher_review', v_status::text);

  begin
    perform public.approve_report_card(v_rc_id);
    call test_util.record('a teacher cannot approve a report card', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot approve a report card', true, v_error);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  perform public.set_report_card_comment(v_rc_id, 'principal_comment', 'Keep it up.');
  select status into v_status from public.approve_report_card(v_rc_id);
  select (locked_at is not null) into v_locked from public.report_cards where id = v_rc_id;
  call test_util.record('the principal can approve; card is approved + locked',
    v_status = 'approved' and v_locked, v_status::text);

  begin
    perform public.recalculate_report_card(v_rc_id);
    call test_util.record('recalculate is rejected once approved (locked)', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('recalculate is rejected once approved (locked)', true, v_error);
  end;
  begin
    perform public.set_report_card_comment(v_rc_id, 'principal_comment', 'changed my mind');
    call test_util.record('editing a comment is rejected once approved (locked)', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('editing a comment is rejected once approved (locked)', true, v_error);
  end;

  select status into v_status from public.publish_report_card(v_rc_id);
  call test_util.record('the principal can publish an approved card', v_status = 'published', v_status::text);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Visibility: guardian sees the published card + subjects; never a
-- non-published one.
do $$
declare v_rc_id uuid; v_seen int; v_subj_seen int;
begin
  select id into v_rc_id from public.report_cards
    where learner_id = 'bc110000-0000-0000-0000-000000000001' and status = 'published' limit 1;

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('bc110000-0000-0000-0000-0000000000a2', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.report_cards where id = v_rc_id;
  select count(*) into v_subj_seen from public.report_card_subjects where report_card_id = v_rc_id;
  call test_util.record('a guardian sees their child''s published report card', v_seen = 1, 'rows: ' || v_seen);
  call test_util.record('a guardian sees the published card''s subject rows', v_subj_seen >= 1, 'rows: ' || v_subj_seen);

  select count(*) into v_seen from public.report_cards where learner_id = 'bc110000-0000-0000-0000-000000000001' and status <> 'published';
  call test_util.record('a guardian never sees a non-published card', v_seen = 0, 'rows: ' || v_seen);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. HOD-review path + learner-self visibility.
do $$
declare v_rc public.report_cards; v_error text; v_status public.report_card_status; v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select * into v_rc from public.generate_report_card(
    'bc110000-0000-0000-0000-000000000002', '70000000-0000-0000-0000-000000000001', '4c1d0000-0000-0000-0000-0000000ab002');
  perform public.submit_report_card(v_rc.id);

  begin
    perform public.approve_report_card(v_rc.id);
    call test_util.record('a requires-HOD template blocks approval from teacher_review', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a requires-HOD template blocks approval from teacher_review', true, v_error);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('d0d0d0d0-0000-0000-0000-000000000001', 'department_head', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select status into v_status from public.review_report_card(v_rc.id, true, 'Looks good');
  call test_util.record('a department_head advances the card to hod_review', v_status = 'hod_review', v_status::text);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select status into v_status from public.approve_report_card(v_rc.id);
  call test_util.record('the principal can approve after HOD review', v_status = 'approved', v_status::text);
  perform public.publish_report_card(v_rc.id);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('bc110000-0000-0000-0000-0000000000a3', 'learner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.report_cards where learner_id = 'bc110000-0000-0000-0000-000000000002' and status = 'published';
  call test_util.record('a learner sees their own published report card', v_count = 1, 'rows: ' || v_count);
  select count(*) into v_count from public.report_cards where learner_id = 'bc110000-0000-0000-0000-000000000001';
  call test_util.record('a learner does not see another learner''s report card', v_count = 0, 'rows: ' || v_count);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. Reissue: creates v2 in draft, archives + supersedes v1, one live card.
do $$
declare v_old_id uuid; v_new public.report_cards; v_old public.report_cards; v_live int;
begin
  select id into v_old_id from public.report_cards
    where learner_id = 'bc110000-0000-0000-0000-000000000001' and status = 'published' limit 1;

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select * into v_new from public.reissue_report_card(v_old_id, 'Mark capture error on the exam');
  select * into v_old from public.report_cards where id = v_old_id;

  call test_util.record('reissue produces a v2 draft', v_new.version = 2 and v_new.status = 'draft', format('v%s %s', v_new.version, v_new.status));
  call test_util.record('the original card is archived and superseded', v_old.status = 'archived' and v_old.superseded_by = v_new.id, v_old.status::text);

  select count(*) into v_live from public.report_cards
    where learner_id = 'bc110000-0000-0000-0000-000000000001' and template_id = '4c1d0000-0000-0000-0000-0000000ab001' and status <> 'archived';
  call test_util.record('exactly one live card exists after reissue', v_live = 1, 'live: ' || v_live);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 8. A direct client UPDATE / DELETE on report_cards changes nothing —
-- there is no UPDATE/DELETE policy (RLS silently affects 0 rows), and the
-- report_cards_protect trigger is the backstop if one were ever added.
do $$
declare v_rc_id uuid; v_before public.report_card_status; v_after public.report_card_status;
        v_upd int; v_del int; v_still_there int; v_trigger_ok boolean := false; v_error text;
begin
  select id, status into v_rc_id, v_before from public.report_cards where learner_id = 'bc110000-0000-0000-0000-000000000001' limit 1;
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.report_cards set status = 'published' where id = v_rc_id;
  get diagnostics v_upd = row_count;
  select status into v_after from public.report_cards where id = v_rc_id;
  call test_util.record('a direct client UPDATE to a report card changes nothing',
    v_upd = 0 and v_after = v_before, format('rows=%s status %s->%s', v_upd, v_before, v_after));

  delete from public.report_cards where id = v_rc_id;
  get diagnostics v_del = row_count;
  select count(*) into v_still_there from public.report_cards where id = v_rc_id;
  call test_util.record('a direct client DELETE of a report card removes nothing',
    v_del = 0 and v_still_there = 1, format('rows=%s remaining=%s', v_del, v_still_there));
  execute 'reset role';

  -- Trigger backstop: even the table owner is stopped without the write guard.
  begin
    update public.report_cards set principal_comment = 'forced' where id = v_rc_id;
    call test_util.record('the report_cards_protect trigger blocks an unguarded write', false, 'update succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('the report_cards_protect trigger blocks an unguarded write', true, v_error);
  end;
end $$;
