-- Regression suite for 20260905090000_admissions.sql.
--
-- Reuses stable fixtures: School A aaaaaaaa, year aaaa1111...0001, grade
-- aaaa2222...0001, class cccc1111...0001, School B bbbbbbbb, teacher A1
-- 11111111 (no admissions access). Creates its own admissions_officer,
-- receptionist and a School B admissions_officer.

do $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', 'ad0f0000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'adm.a1@schoola.test',
     jsonb_build_object('role', 'admissions_officer', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
    ('00000000-0000-0000-0000-000000000000', 'ad0f0000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'recep.a1@schoola.test',
     jsonb_build_object('role', 'receptionist', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')),
    ('00000000-0000-0000-0000-000000000000', 'ad0f0000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'adm.b1@schoolb.test',
     jsonb_build_object('role', 'admissions_officer', 'tenant_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('ad0f0000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Adm', 'A1', 'adm.a1@schoola.test', 'admissions_officer', 'active'),
    ('ad0f0000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Recep', 'A1', 'recep.a1@schoola.test', 'receptionist', 'active'),
    ('ad0f0000-0000-0000-0000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Adm', 'B1', 'adm.b1@schoolb.test', 'admissions_officer', 'active');
end $$;

-- ---------------------------------------------------------------------------
-- 1. Full staff workflow: create -> submit -> under_review -> accepted ->
-- convert. Verifies the learner + guardian + enrolment are produced.
do $$
declare v_app public.admission_applications; v_ref text; v_learner_count int; v_link_count int; v_enrol_count int; v_final_status public.admission_application_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000001', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select * into v_app from public.create_admission_application(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'convert.parent@family.test', 'Pam', 'Parent', 'Kid', 'ToConvert',
    'aaaa1111-0000-0000-0000-000000000001', 'aaaa2222-0000-0000-0000-000000000001', '0821112222', 'mother', '2021-05-01');
  call test_util.record('admissions_officer can create a draft application', v_app.status = 'draft', v_app.status::text);

  select reference_number into v_ref from public.submit_admission_application(v_app.id);
  call test_util.record('submit assigns a reference number', v_ref like 'APP-%', coalesce(v_ref, 'null'));

  perform public.transition_admission_application(v_app.id, 'under_review', null);
  perform public.transition_admission_application(v_app.id, 'accepted', 'strong candidate');

  perform public.convert_admission_application(v_app.id, 'cccc1111-0000-0000-0000-000000000001', false);

  select count(*) into v_learner_count from public.learners
    where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and first_name = 'Kid' and last_name = 'ToConvert';
  select count(*) into v_link_count from public.learner_guardians lg
    join public.learners l on l.id = lg.learner_id where l.first_name = 'Kid' and l.last_name = 'ToConvert';
  select count(*) into v_enrol_count from public.learner_enrollments le
    join public.learners l on l.id = le.learner_id where l.first_name = 'Kid' and l.last_name = 'ToConvert';

  call test_util.record('conversion creates exactly one learner', v_learner_count = 1, 'learners: ' || v_learner_count);
  call test_util.record('conversion links a guardian', v_link_count = 1, 'links: ' || v_link_count);
  call test_util.record('conversion creates an enrolment', v_enrol_count = 1, 'enrolments: ' || v_enrol_count);
  select status into v_final_status from public.admission_applications where id = v_app.id;
  call test_util.record('a converted application is enrolled', v_final_status = 'enrolled', v_final_status::text);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Converting twice is rejected.
do $$
declare v_app_id uuid; v_error text;
begin
  select id into v_app_id from public.admission_applications where applicant_email = 'convert.parent@family.test';
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000001', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.convert_admission_application(v_app_id);
    call test_util.record('a converted application cannot be converted again', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a converted application cannot be converted again', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. An illegal status transition is rejected.
do $$
declare v_app public.admission_applications; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000001', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select * into v_app from public.create_admission_application(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'badtransition@family.test', 'P', 'P', 'K', 'K');
  begin
    perform public.transition_admission_application(v_app.id, 'accepted', 'skipping submit');
    call test_util.record('cannot jump a draft straight to accepted', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('cannot jump a draft straight to accepted', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. A direct client UPDATE to status is blocked by the protect trigger.
do $$
declare v_app_id uuid; v_error text; v_after public.admission_application_status;
begin
  select id into v_app_id from public.admission_applications where applicant_email = 'badtransition@family.test';
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000001', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    update public.admission_applications set status = 'accepted' where id = v_app_id;
    call test_util.record('a direct client status UPDATE is blocked', false, 'update succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a direct client status UPDATE is blocked', true, v_error);
  end;
  -- but editing the free-text data on a draft is allowed
  update public.admission_applications set prior_school = 'Little School' where id = v_app_id;
  select status into v_after from public.admission_applications where id = v_app_id;
  call test_util.record('editing draft data directly is allowed and does not change status', v_after = 'draft', v_after::text);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. A receptionist can view but not manage; a teacher sees nothing.
do $$
declare v_seen int; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000002', 'receptionist', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.admission_applications;
  call test_util.record('a receptionist can view applications', v_seen >= 1, 'rows: ' || v_seen);
  begin
    perform public.create_admission_application('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'x@y.test', 'A', 'B', 'C', 'D');
    call test_util.record('a receptionist cannot create an application', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a receptionist cannot create an application', true, v_error);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.admission_applications;
  call test_util.record('a teacher sees no applications', v_seen = 0, 'rows: ' || v_seen);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Cross-tenant: School B's admissions_officer sees none of School A's.
do $$
declare v_seen int; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000003', 'admissions_officer', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.admission_applications where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('School B cannot see School A applications', v_seen = 0, 'rows: ' || v_seen);
  begin
    perform public.create_admission_application('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'x@y.test', 'A', 'B', 'C', 'D');
    call test_util.record('School B cannot create a School A application', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B cannot create a School A application', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. next_admission_reference is internal — not callable by a client.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000001', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.next_admission_reference('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    call test_util.record('an authenticated client cannot call next_admission_reference', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an authenticated client cannot call next_admission_reference', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 8. The public intake RPCs (service_role) round-trip start -> save ->
-- submit -> resume, and reject a wrong-email resume.
do $$
declare v_started jsonb; v_token uuid; v_submitted jsonb; v_resumed jsonb; v_wrong jsonb;
begin
  -- Run the public RPCs as service_role, capture everything, then reset to
  -- the harness owner before recording (service_role lacks test_util access).
  execute 'set local role service_role';
  v_started := public.public_start_admission_application(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'public.parent@family.test',
    jsonb_build_object('applicant_first_name', 'Pat', 'learner_first_name', 'Pip', 'learner_last_name', 'Public'));
  v_token := (v_started->>'resume_token')::uuid;
  perform public.public_save_admission_application(v_token, jsonb_build_object('applicant_last_name', 'Public'));
  v_submitted := public.public_submit_admission_application(v_token);
  v_resumed := public.public_resume_admission_application('public.parent@family.test', v_submitted->>'reference_number');
  v_wrong := public.public_resume_admission_application('someone.else@family.test', v_submitted->>'reference_number');
  execute 'reset role';

  call test_util.record('public submit assigns a reference', (v_submitted->>'reference_number') like 'APP-%', v_submitted::text);
  call test_util.record('public resume finds the application by email + reference', (v_resumed->>'found')::boolean, v_resumed->>'status');
  call test_util.record('a submitted application returns no resume token', v_resumed->>'resume_token' is null, coalesce(v_resumed->>'resume_token', 'null'));
  call test_util.record('public resume rejects a wrong email', (v_wrong->>'found')::boolean = false, v_wrong::text);
end $$;

-- ---------------------------------------------------------------------------
-- 9. The public intake RPCs are NOT callable by an ordinary authenticated
-- client (service_role only).
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('ad0f0000-0000-0000-0000-000000000001', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.public_start_admission_application('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'x@y.test', '{}'::jsonb);
    call test_util.record('an authenticated client cannot call the public intake RPC', false, 'succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an authenticated client cannot call the public intake RPC', true, v_error);
  end;
  execute 'reset role';
end $$;
