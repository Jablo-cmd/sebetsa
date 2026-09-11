-- Regression suite for the Homework / Learning domain
-- (20260908090000_homework.sql): assignments + their draft/published/closed
-- lifecycle, the RPC-only submission workflow, can_manage_homework class
-- scoping, guardian/learner visibility, the gradebook (assessment_results)
-- sync, and the protect triggers.
--
-- Fixtures (School A tenant aaaa..., year aaaa1111...0001, term
-- 70000000...0001, subject facade00...0001, class cccc1111...0001):
--   11111111  teacher A1  — class_teacher_assignments a771e000...0001 -> class cccc1111...0001
--   12121212  teacher A2  — deliberately unassigned to any class
--   22222222  school_owner A1
--   55555555 / 59595959   — guardians of learner 11110000...0001 (enrolled in the class)
--   33333333  teacher B1 (School B), 18181818 parent (School B)

-- ---------------------------------------------------------------------------
-- 1. A class teacher creates a draft assignment for their class.
do $$
declare v_id uuid; v_status public.assignment_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
    'Fractions worksheet', 'Complete questions 1-10.', now() + interval '3 days', 10,
    '70000000-0000-0000-0000-000000000001')).id into v_id;
  select status into v_status from public.assignments where id = v_id;
  execute 'reset role';
  call test_util.record('a class teacher creates a draft assignment', v_status = 'draft', 'status: ' || coalesce(v_status::text, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. A teacher not assigned to the class cannot create an assignment for it.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('12121212-1212-1212-1212-121212121212', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.create_assignment(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
      'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Rogue task');
    call test_util.record('an unassigned teacher cannot create an assignment for the class', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an unassigned teacher cannot create an assignment for the class', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Publishing fans out one 'assigned' submission per enrolled learner and
--    notifies the learner's guardians.
do $$
declare
  v_id uuid;
  v_for_learner int;
  v_all_have_status boolean;
  v_notif_5555 int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001',
    'Reading log', 'Read for 20 minutes.', now() + interval '2 days', null,
    '70000000-0000-0000-0000-000000000001')).id into v_id;
  perform public.publish_assignment(v_id);
  execute 'reset role';

  select count(*) into v_for_learner from public.assignment_submissions
    where assignment_id = v_id and learner_id = '11110000-0000-0000-0000-000000000001';
  select bool_and(status = 'assigned') into v_all_have_status from public.assignment_submissions where assignment_id = v_id;
  select count(*) into v_notif_5555 from public.notifications
    where recipient_profile_id = '55555555-5555-5555-5555-555555555555' and type = 'assignment_published' and related_entity_id = v_id;

  call test_util.record('publishing creates an assigned submission for the enrolled learner', v_for_learner = 1, 'rows: ' || v_for_learner);
  call test_util.record('every fanned-out submission starts as assigned', v_all_have_status, 'all assigned: ' || coalesce(v_all_have_status::text, 'null'));
  call test_util.record('publishing notifies the learner''s guardian', v_notif_5555 = 1, 'notifs: ' || v_notif_5555);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A guardian sees a published assignment their child is on, but not a draft.
do $$
declare v_draft uuid; v_published uuid; v_sees_draft int; v_sees_published int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Secret draft')).id into v_draft;
  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Visible homework',
    null, now() + interval '5 days')).id into v_published;
  perform public.publish_assignment(v_published);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_sees_draft from public.assignments where id = v_draft;
  select count(*) into v_sees_published from public.assignments where id = v_published;
  execute 'reset role';

  call test_util.record('a guardian cannot see a draft assignment', v_sees_draft = 0, 'visible: ' || v_sees_draft);
  call test_util.record('a guardian can see a published assignment their child is on', v_sees_published = 1, 'visible: ' || v_sees_published);
end $$;

-- ---------------------------------------------------------------------------
-- 5. A guardian submits on their child's behalf; the status is 'submitted'
--    (due date in the future). A guardian from another family cannot.
do $$
declare v_id uuid; v_sub_status public.assignment_submission_status; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Poster project',
    null, now() + interval '7 days', 20)).id into v_id;
  perform public.publish_assignment(v_id);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  perform public.submit_assignment(v_id, '11110000-0000-0000-0000-000000000001', 'Poster attached.');
  execute 'reset role';
  select status into v_sub_status from public.assignment_submissions where assignment_id = v_id and learner_id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('a guardian can submit on behalf of their child (on time)', v_sub_status = 'submitted', 'status: ' || coalesce(v_sub_status::text, 'null'));

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('18181818-1818-1818-1818-181818181818', 'parent', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.submit_assignment(v_id, '11110000-0000-0000-0000-000000000001', 'not my child');
    call test_util.record('a guardian from another family cannot submit', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a guardian from another family cannot submit', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Resubmission is refused when the assignment does not allow it.
do $$
declare v_id uuid; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'One-shot task',
    null, now() + interval '7 days')).id into v_id;
  perform public.publish_assignment(v_id);
  perform public.submit_assignment(v_id, '11110000-0000-0000-0000-000000000001', 'first');
  begin
    perform public.submit_assignment(v_id, '11110000-0000-0000-0000-000000000001', 'second');
    call test_util.record('a second submission is refused when resubmission is off', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a second submission is refused when resubmission is off', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. Marking sets points + 'reviewed', notifies guardians, and — when the
--    assignment is linked to an assessment — syncs assessment_results.
do $$
declare
  v_assessment uuid;
  v_assignment uuid;
  v_sub uuid;
  v_status public.assignment_submission_status;
  v_points int;
  v_result_mark int;
  v_notif int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.assessments (school_id, academic_year_id, term_id, class_id, subject_id, title, assessment_type, assessment_date, max_mark)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaa1111-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001',
            'cccc1111-0000-0000-0000-000000000001', 'facade00-0000-0000-0000-000000000001', 'Graded homework', 'assignment', current_date, 20)
    returning id into v_assessment;

  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Graded homework',
    null, now() + interval '2 days', 20, '70000000-0000-0000-0000-000000000001', false, '[]'::jsonb, v_assessment)).id into v_assignment;
  perform public.publish_assignment(v_assignment);
  perform public.submit_assignment(v_assignment, '11110000-0000-0000-0000-000000000001', 'done');

  select id into v_sub from public.assignment_submissions where assignment_id = v_assignment and learner_id = '11110000-0000-0000-0000-000000000001';
  perform public.mark_assignment_submission(v_sub, 17, 'Good work.', null, true);
  execute 'reset role';

  select status, points_awarded into v_status, v_points from public.assignment_submissions where id = v_sub;
  select mark into v_result_mark from public.assessment_results where assessment_id = v_assessment and learner_id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_notif from public.notifications
    where recipient_profile_id = '55555555-5555-5555-5555-555555555555' and type = 'assignment_reviewed' and related_entity_id = v_assignment;

  call test_util.record('marking finalises the submission as reviewed', v_status = 'reviewed', 'status: ' || coalesce(v_status::text, 'null'));
  call test_util.record('marking records the points awarded', v_points = 17, 'points: ' || coalesce(v_points::text, 'null'));
  call test_util.record('marking a linked assignment syncs assessment_results', v_result_mark = 17, 'mark: ' || coalesce(v_result_mark::text, 'null'));
  call test_util.record('marking notifies the learner''s guardian', v_notif = 1, 'notifs: ' || v_notif);
end $$;

-- ---------------------------------------------------------------------------
-- 8. Submissions and assignment status are RPC-only.
do $$
declare v_id uuid; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Guard test')).id into v_id;

  begin
    insert into public.assignment_submissions (assignment_id, school_id, learner_id)
      values (v_id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001');
    call test_util.record('a direct INSERT into assignment_submissions is rejected', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a direct INSERT into assignment_submissions is rejected', true, 'correctly rejected: ' || v_error);
  end;

  begin
    update public.assignments set status = 'published' where id = v_id;
    call test_util.record('a direct UPDATE of assignments.status is rejected', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a direct UPDATE of assignments.status is rejected', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 9. Cross-tenant isolation.
do $$
declare v_id uuid; v_sees int; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
    'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'School A only')).id into v_id;
  perform public.publish_assignment(v_id);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_sees from public.assignments where id = v_id;
  begin
    perform public.create_assignment('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccc1111-0000-0000-0000-000000000001',
      'facade00-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'cross tenant');
    call test_util.record('a School B teacher cannot create a School A assignment', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a School B teacher cannot create a School A assignment', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
  call test_util.record('a School B teacher cannot see a School A assignment', v_sees = 0, 'visible: ' || v_sees);
end $$;
