-- Regression suite for FND-WF-001 (20260829150000_fee_overdue_reminders.sql):
-- run_fee_overdue_reminders() / trigger_fee_overdue_reminders().
--
-- Creates its own dedicated learners + guardians (isolation lesson from
-- attendance_alerts.test.sql — a shared learner's fee ledger from another
-- test file would make outstanding-balance math depend on file execution
-- order). Uses School A academic year aaaa1111...0001 / class
-- cccc1111...0001 (05_learner_fixtures.sql), school_owner 22222222,
-- finance_manager 17171717 (11_fees_behaviour_fixtures.sql), and School B
-- (bbbbbbbb...) for the cross-tenant check.

do $$
begin
  -- Learner 1: charge due 5 days ago, unpaid — reminder tier only.
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', '5b110000-5b11-5b11-5b11-5b110000af01',
     'authenticated', 'authenticated', 'fee-reminder-guardian1@schoola.test',
     jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('5b110000-5b11-5b11-5b11-5b110000af01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Fee', 'Guardian1', 'fee-reminder-guardian1@schoola.test', 'guardian', 'active');
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000af01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-WF01', 'ADM-A-WF01', 'FeeReminder', 'LearnerOne', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('1e110000-0000-0000-0000-00000000af01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000af01', '5b110000-5b11-5b11-5b11-5b110000af01', 'mother', true);
  insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, description, category, amount, due_date) values
    ('c9110000-0000-0000-0000-00000000af01', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000af01', 'aaaa1111-0000-0000-0000-000000000001', 'Term charge', 'tuition', 1000.00, current_date - 5);

  -- Learner 2: charge due 20 days ago, unpaid — reminder AND escalation tier.
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', '5b110000-5b11-5b11-5b11-5b110000af02',
     'authenticated', 'authenticated', 'fee-reminder-guardian2@schoola.test',
     jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('5b110000-5b11-5b11-5b11-5b110000af02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Fee', 'Guardian2', 'fee-reminder-guardian2@schoola.test', 'guardian', 'active');
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000af02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-WF02', 'ADM-A-WF02', 'FeeReminder', 'LearnerTwo', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary) values
    ('1e110000-0000-0000-0000-00000000af02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000af02', '5b110000-5b11-5b11-5b11-5b110000af02', 'mother', true);
  insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, description, category, amount, due_date) values
    ('c9110000-0000-0000-0000-00000000af02', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000af02', 'aaaa1111-0000-0000-0000-000000000001', 'Term charge', 'tuition', 1000.00, current_date - 20);

  -- Learner 3: charge due 20 days ago, but FULLY PAID — outstanding is
  -- zero, so no reminder should fire despite the past due_date.
  insert into public.learners (id, school_id, learner_number, admission_number, first_name, last_name, date_of_birth, status, admission_date) values
    ('11110000-0000-0000-0000-00000000af03', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'LRN-A-WF03', 'ADM-A-WF03', 'FeeReminder', 'LearnerThree', '2014-04-01', 'active', '2024-01-15');
  insert into public.learner_fee_charges (id, school_id, learner_id, academic_year_id, description, category, amount, due_date) values
    ('c9110000-0000-0000-0000-00000000af03', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000af03', 'aaaa1111-0000-0000-0000-000000000001', 'Term charge', 'tuition', 1000.00, current_date - 20);
  insert into public.learner_fee_payments (id, school_id, learner_id, academic_year_id, amount, payment_date, method) values
    ('af110000-0000-0000-0000-00000000af03', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-00000000af03', 'aaaa1111-0000-0000-0000-000000000001', 1000.00, current_date - 19, 'eft');
end $$;

-- ---------------------------------------------------------------------------
-- 1. Running the worker for School A sends: a reminder to guardian 1 (5
-- days overdue, no escalation yet), a reminder AND escalation for guardian
-- 2 / finance_manager (20 days overdue), and nothing for learner 3 (paid).
do $$
declare v_sent int;
declare v_reminder1 int;
declare v_reminder2 int;
declare v_escalation int;
declare v_reminder3 int;
begin
  select public.run_fee_overdue_reminders('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') into v_sent;

  select count(*) into v_reminder1 from public.notifications
    where recipient_profile_id = '5b110000-5b11-5b11-5b11-5b110000af01' and type = 'fee_reminder';
  select count(*) into v_reminder2 from public.notifications
    where recipient_profile_id = '5b110000-5b11-5b11-5b11-5b110000af02' and type = 'fee_reminder';
  select count(*) into v_escalation from public.notifications
    where recipient_profile_id = '17171717-1717-1717-1717-171717171717' and type = 'fee_overdue_escalation'
      and related_entity_id = '11110000-0000-0000-0000-00000000af02';
  select count(*) into v_reminder3 from public.notifications
    where type in ('fee_reminder', 'fee_overdue_escalation') and related_entity_id = '11110000-0000-0000-0000-00000000af03';

  call test_util.record('the worker sent at least the 3 notifications this fixture expects', v_sent >= 3, 'sent: ' || v_sent);
  call test_util.record('a learner 5 days overdue triggers a guardian reminder', v_reminder1 = 1, 'rows: ' || v_reminder1);
  call test_util.record('a learner 20 days overdue triggers a guardian reminder too', v_reminder2 = 1, 'rows: ' || v_reminder2);
  call test_util.record('a learner 20 days overdue also escalates to finance_manager', v_escalation = 1, 'rows: ' || v_escalation);
  call test_util.record('a fully-paid overdue charge never triggers a reminder or escalation', v_reminder3 = 0, 'rows: ' || v_reminder3);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Running it again immediately sends nothing new — both cooldowns
-- (7-day reminder, 14-day escalation) are still active.
do $$
declare v_sent int;
begin
  select public.run_fee_overdue_reminders('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') into v_sent;
  call test_util.record('re-running immediately sends nothing new (cooldown)', v_sent = 0, 'sent: ' || v_sent);
end $$;

-- ---------------------------------------------------------------------------
-- 3. trigger_fee_overdue_reminders(): a teacher (no financial-manage
-- permission) is rejected; a finance_manager succeeds (0 sent, cooldown
-- still active — proves authorization passed, not that nothing happened).
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.trigger_fee_overdue_reminders('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    call test_util.record('a teacher cannot trigger fee overdue reminders', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot trigger fee overdue reminders', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

do $$
declare v_sent int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('17171717-1717-1717-1717-171717171717', 'finance_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select public.trigger_fee_overdue_reminders('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') into v_sent;
  execute 'reset role';
  call test_util.record('finance_manager can trigger fee overdue reminders for their own school', v_sent = 0, 'sent: ' || v_sent || ' (0 expected — cooldown, proves authorization passed)');
end $$;

-- ---------------------------------------------------------------------------
-- 4. School B's finance_manager cannot trigger reminders for School A.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.trigger_fee_overdue_reminders('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    call test_util.record('School B''s finance_manager cannot trigger reminders for School A', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s finance_manager cannot trigger reminders for School A', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;
