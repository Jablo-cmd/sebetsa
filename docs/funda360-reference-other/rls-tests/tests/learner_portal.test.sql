-- Regression suite for the Learner Portal domain
-- (20260910090000_learner_portal.sql): provision_learner_login, the
-- is_learner_self SELECT policies, and the announcements `all_staff`
-- exclusion of the `learner` role.
--
-- Fixtures: learner A1 11110000...0001 (enrolled in class cccc1111...0001,
-- guardians 55555555 / 59595959, NO profile_id yet); learner A2
-- 11110000...0002 (profile 30303030...30, role learner, already linked);
-- teacher A1 11111111; school_owner 22222222.

-- ---------------------------------------------------------------------------
-- 1. Staff provision a login for learner A1; a second attempt is rejected.
do $$
declare v_uid uuid; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select user_id into v_uid from public.provision_learner_login('11110000-0000-0000-0000-000000000001', 'lernA1@schoola.test');
  call test_util.record('staff can provision a learner login', v_uid is not null, 'uid: ' || coalesce(v_uid::text, 'null'));

  begin
    perform public.provision_learner_login('11110000-0000-0000-0000-000000000001', 'again@schoola.test');
    call test_util.record('provisioning a second login for the same learner is rejected', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provisioning a second login for the same learner is rejected', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';

  -- The learners row now points at a learner-role profile.
  declare v_role public.user_role; v_linked uuid;
  begin
    select profile_id into v_linked from public.learners where id = '11110000-0000-0000-0000-000000000001';
    select role into v_role from public.profiles where id = v_linked;
    call test_util.record('the provisioned profile has the learner role', v_role = 'learner', 'role: ' || coalesce(v_role::text, 'null'));
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 2. A non-manager (teacher) cannot provision a learner login.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.provision_learner_login('11110000-0000-0000-0000-000000000002', 'x@schoola.test');
    call test_util.record('a teacher cannot provision a learner login', false, 'succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot provision a learner login', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. The provisioned learner sees their own data — exactly the rows a
--    manager sees for that learner — and nothing for another learner.
do $$
declare
  v_me uuid;
  v_staff_att int; v_self_att int;
  v_staff_res int; v_self_res int;
  v_staff_enr int; v_self_enr int;
  v_sees_self int; v_sees_other int;
  v_sees_reference int;
begin
  select profile_id into v_me from public.learners where id = '11110000-0000-0000-0000-000000000001';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_staff_att from public.attendance_records where learner_id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_staff_res from public.assessment_results where learner_id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_staff_enr from public.learner_enrollments where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims(v_me, 'learner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_sees_self from public.learners where id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_sees_other from public.learners where id = '11110000-0000-0000-0000-000000000002';
  select count(*) into v_self_att from public.attendance_records where learner_id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_self_res from public.assessment_results where learner_id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_self_enr from public.learner_enrollments where learner_id = '11110000-0000-0000-0000-000000000001';
  select count(*) into v_sees_reference from public.classes where id = 'cccc1111-0000-0000-0000-000000000001';
  execute 'reset role';

  call test_util.record('a learner sees their own learner record', v_sees_self = 1, 'rows: ' || v_sees_self);
  call test_util.record('a learner does not see another learner''s record', v_sees_other = 0, 'rows: ' || v_sees_other);
  call test_util.record('a learner sees exactly their own enrolments', v_self_enr = v_staff_enr and v_self_enr >= 1, 'self ' || v_self_enr || ' vs staff ' || v_staff_enr);
  call test_util.record('a learner sees exactly their own attendance rows', v_self_att = v_staff_att, 'self ' || v_self_att || ' vs staff ' || v_staff_att);
  call test_util.record('a learner sees exactly their own assessment results', v_self_res = v_staff_res, 'self ' || v_self_res || ' vs staff ' || v_staff_res);
  call test_util.record('a learner can see their class as reference data', v_sees_reference = 1, 'rows: ' || v_sees_reference);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A learner does NOT receive or see an all_staff announcement.
do $$
declare v_id uuid; v_sees int; v_notif int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.announcements (school_id, title, body, audience)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Staff briefing', 'Staffroom 07:30.', 'all_staff')
    returning id into v_id;
  execute 'reset role';

  select count(*) into v_notif from public.notifications
    where recipient_profile_id = '30303030-3030-3030-3030-303030303030' and type = 'announcement' and related_entity_id = v_id;

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('30303030-3030-3030-3030-303030303030', 'learner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_sees from public.announcements where id = v_id;
  execute 'reset role';

  call test_util.record('a learner is not notified of an all_staff announcement', v_notif = 0, 'notifs: ' || v_notif);
  call test_util.record('a learner cannot see an all_staff announcement', v_sees = 0, 'visible: ' || v_sees);
end $$;

-- ---------------------------------------------------------------------------
-- 5. A learner DOES see an `everyone` announcement, routed to /learner/announcements.
do $$
declare v_id uuid; v_link text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.announcements (school_id, title, body, audience)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'School closed Friday', 'Public holiday.', 'everyone')
    returning id into v_id;
  execute 'reset role';

  select link_path into v_link from public.notifications
    where recipient_profile_id = '30303030-3030-3030-3030-303030303030' and type = 'announcement' and related_entity_id = v_id;
  call test_util.record('a learner''s everyone-announcement link routes to the Learner Portal', v_link = '/learner/announcements', 'link: ' || coalesce(v_link, 'null'));
end $$;
