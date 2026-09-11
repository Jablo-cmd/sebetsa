-- Regression suite for FND-DOC-002 (20260829160000_document_expiry_alerts.sql):
-- run_document_expiry_alerts() / trigger_document_expiry_alerts().
--
-- Creates its own dedicated learners + guardians (same isolation lesson as
-- fee_overdue_reminders.test.sql / attendance_alerts.test.sql). Uses
-- School A (school_owner 22222222 — 02_fixtures.sql), School B
-- (finance_manager 16161616 — 11_fees_behaviour_fixtures.sql, used only to
-- prove a financial role is NOT authorized here, unlike FND-WF-001).

do $$
begin
  -- Learner 1: a document expiring in 10 days — expiring-soon tier only.
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', '5c110000-5c11-5c11-5c11-5c110000ae01',
     'authenticated', 'authenticated', 'doc-expiry-guardian1@schoola.test',
     jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('5c110000-5c11-5c11-5c11-5c110000ae01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Doc', 'Guardian1', 'doc-expiry-guardian1@schoola.test', 'guardian', 'active');
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000ae01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-AE01', 'ADM-A-AE01', 'DocExpiry', 'LearnerOne', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('1e110000-0000-0000-0000-00000000ae01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000ae01', '5c110000-5c11-5c11-5c11-5c110000ae01', 'mother', true);
  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name, expiry_date) values
    ('d0110000-0000-0000-0000-00000000ae01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000ae01', 'passport', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-00000000ae01/passport.pdf', 'passport.pdf', current_date + 10);

  -- Learner 2: a document that expired 5 days ago — expired tier (staff).
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000ae02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-AE02', 'ADM-A-AE02', 'DocExpiry', 'LearnerTwo', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name, expiry_date) values
    ('d0110000-0000-0000-0000-00000000ae02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000ae02', 'permit', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-00000000ae02/permit.pdf', 'permit.pdf', current_date - 5);

  -- Learner 3: a document expiring in 90 days — outside the 30-day
  -- reminder window, should generate nothing at all yet.
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000ae03', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-AE03', 'ADM-A-AE03', 'DocExpiry', 'LearnerThree', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_documents (id, school_id, learner_id, document_type, file_url, file_name, expiry_date) values
    ('d0110000-0000-0000-0000-00000000ae03', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000ae03', 'medical_certificate', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/11110000-0000-0000-0000-00000000ae03/med.pdf', 'med.pdf', current_date + 90);
end $$;

-- ---------------------------------------------------------------------------
-- 1. Running the worker for School A: guardian 1 gets an expiring-soon
-- reminder, school_owner (can_manage_learners) gets an expired alert for
-- learner 2, and nothing fires for learner 3 (outside the 30-day window).
do $$
declare v_reminder1 int;
declare v_expired2 int;
declare v_nothing3 int;
begin
  perform public.run_document_expiry_alerts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

  select count(*) into v_reminder1 from public.notifications
    where recipient_profile_id = '5c110000-5c11-5c11-5c11-5c110000ae01' and type = 'document_expiring_soon';
  select count(*) into v_expired2 from public.notifications
    where recipient_profile_id = '22222222-2222-2222-2222-222222222222' and type = 'document_expired'
      and related_entity_id = 'd0110000-0000-0000-0000-00000000ae02';
  select count(*) into v_nothing3 from public.notifications
    where related_entity_id = 'd0110000-0000-0000-0000-00000000ae03';

  call test_util.record('a document expiring in 10 days reminds the guardian', v_reminder1 = 1, 'rows: ' || v_reminder1);
  call test_util.record('a document expired 5 days ago alerts school_owner', v_expired2 = 1, 'rows: ' || v_expired2);
  call test_util.record('a document expiring in 90 days (outside the 30-day window) triggers nothing yet', v_nothing3 = 0, 'rows: ' || v_nothing3);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Re-running immediately sends nothing new for either tier (cooldowns).
do $$
declare v_sent int;
begin
  select public.run_document_expiry_alerts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') into v_sent;
  call test_util.record('re-running immediately sends nothing new (cooldown)', v_sent = 0, 'sent: ' || v_sent);
end $$;

-- ---------------------------------------------------------------------------
-- 3. trigger_document_expiry_alerts(): a finance_manager (financial-manage
-- permission, but not learner-manage) is rejected — this workflow's
-- authorization is deliberately different from FND-WF-001's.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.trigger_document_expiry_alerts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    call test_util.record('a finance_manager cannot trigger document expiry alerts', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a finance_manager cannot trigger document expiry alerts', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

do $$
declare v_sent int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select public.trigger_document_expiry_alerts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') into v_sent;
  execute 'reset role';
  call test_util.record('school_owner can trigger document expiry alerts for their own school', v_sent = 0, 'sent: ' || v_sent || ' (0 expected — cooldown, proves authorization passed)');
end $$;

-- ---------------------------------------------------------------------------
-- 4. School B's finance_manager cannot trigger alerts for School A.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.trigger_document_expiry_alerts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    call test_util.record('School B''s finance_manager cannot trigger alerts for School A', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s finance_manager cannot trigger alerts for School A', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;
