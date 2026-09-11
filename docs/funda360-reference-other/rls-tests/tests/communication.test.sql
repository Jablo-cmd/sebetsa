-- Regression suite for the Communication & Notifications domain
-- (20260907090000_communication.sql): threaded messaging, its
-- participant-scoped RLS + RPC-only write path + can_message_profile()
-- rules, notification_preferences own-row RLS,
-- school_messaging_settings management-only writes, and the
-- notification_deliveries enqueue that create_notification() now performs.
--
-- Fixtures used (School A tenant aaaa..., School B tenant bbbb...):
--   11111111  teacher     (School A)   -- staff
--   22222222  school_owner (School A)
--   55555555  parent      (School A)   -- guardian of Learner A1
--   59595959  guardian    (School A)   -- also guardian of Learner A1
--   33333333  teacher     (School B)
--   66666666  school_owner (School B)
--   44444444  platform admin (no tenant)

-- ---------------------------------------------------------------------------
-- 1. A staff member can start a conversation with a guardian; the guardian
--    receives a 'message' notification and can read the thread.
do $$
declare
  v_conv uuid;
  v_msg_count int;
  v_notif_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(
    array['55555555-5555-5555-5555-555555555555']::uuid[],
    'Hello, could we discuss A1''s progress?', 'Progress check', 'direct')).id
    into v_conv;
  execute 'reset role';

  call test_util.record('staff can start a conversation with a guardian', v_conv is not null, 'conv: ' || coalesce(v_conv::text, 'null'));

  select count(*) into v_notif_count from public.notifications
    where recipient_profile_id = '55555555-5555-5555-5555-555555555555'
      and type = 'message' and related_entity_id = v_conv;
  call test_util.record('the guardian gets exactly one message notification', v_notif_count = 1, 'notifs: ' || v_notif_count);

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_msg_count from public.messages where conversation_id = v_conv;
  execute 'reset role';
  call test_util.record('the guardian can read the thread they are a participant of', v_msg_count = 1, 'messages: ' || v_msg_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. A guardian CANNOT start a conversation with another guardian.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.start_conversation(array['59595959-5959-5959-5959-595959595959']::uuid[], 'Hi neighbour', null, 'direct');
    call test_util.record('a guardian cannot message another guardian', false, 'start_conversation succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a guardian cannot message another guardian', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. A guardian CAN start a conversation with staff.
do $$
declare v_conv uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(array['11111111-1111-1111-1111-111111111111']::uuid[], 'Question about homework', null, 'direct')).id into v_conv;
  execute 'reset role';
  call test_util.record('a guardian can start a conversation with staff', v_conv is not null, 'conv: ' || coalesce(v_conv::text, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant: a staff member cannot message a profile in another school.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.start_conversation(array['66666666-6666-6666-6666-666666666666']::uuid[], 'cross tenant', null, 'direct');
    call test_util.record('a staff member cannot message across tenants', false, 'start_conversation succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a staff member cannot message across tenants', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. A non-participant (School B teacher) cannot see a School A conversation
--    or its messages.
do $$
declare
  v_conv uuid;
  v_visible_conv int;
  v_visible_msgs int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(array['11111111-1111-1111-1111-111111111111']::uuid[], 'Private matter', null, 'direct')).id into v_conv;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_visible_conv from public.conversations where id = v_conv;
  select count(*) into v_visible_msgs from public.messages where conversation_id = v_conv;
  execute 'reset role';

  call test_util.record('a non-participant cannot see the conversation', v_visible_conv = 0, 'visible: ' || v_visible_conv);
  call test_util.record('a non-participant cannot see its messages', v_visible_msgs = 0, 'visible: ' || v_visible_msgs);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Messages / conversations are RPC-only: a direct client INSERT fails.
do $$
declare v_error text; v_conv uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(array['55555555-5555-5555-5555-555555555555']::uuid[], 'seed', null, 'direct')).id into v_conv;
  begin
    insert into public.messages (conversation_id, school_id, sender_profile_id, body)
    values (v_conv, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'direct insert');
    call test_util.record('a direct INSERT into messages is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a direct INSERT into messages is rejected', true, 'correctly rejected: ' || v_error);
  end;
  begin
    insert into public.conversations (school_id, kind) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'direct');
    call test_util.record('a direct INSERT into conversations is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a direct INSERT into conversations is rejected', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. A participant may advance their own read cursor but not another
--    participant's row, and cannot repoint their row to a different
--    conversation (protect trigger).
do $$
declare v_conv uuid; v_error text; v_rows int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(array['55555555-5555-5555-5555-555555555555']::uuid[], 'cursor test', null, 'direct')).id into v_conv;

  update public.conversation_participants set last_read_at = now()
    where conversation_id = v_conv and profile_id = '11111111-1111-1111-1111-111111111111';
  get diagnostics v_rows = row_count;
  call test_util.record('a participant can advance their own read cursor', v_rows = 1, 'rows: ' || v_rows);

  update public.conversation_participants set last_read_at = now()
    where conversation_id = v_conv and profile_id = '55555555-5555-5555-5555-555555555555';
  get diagnostics v_rows = row_count;
  call test_util.record('a participant cannot update another participant''s row', v_rows = 0, 'rows: ' || v_rows);

  begin
    update public.conversation_participants set profile_id = '22222222-2222-2222-2222-222222222222'
      where conversation_id = v_conv and profile_id = '11111111-1111-1111-1111-111111111111';
    call test_util.record('a participant cannot repoint their participant row', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a participant cannot repoint their participant row', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 8. Only the sender can edit or delete a message.
do $$
declare v_conv uuid; v_msg uuid; v_error text; v_body text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(array['55555555-5555-5555-5555-555555555555']::uuid[], 'edit test', null, 'direct')).id into v_conv;
  select id into v_msg from public.messages where conversation_id = v_conv order by created_at desc limit 1;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.edit_message(v_msg, 'rewritten by the wrong person');
    call test_util.record('a non-sender cannot edit a message', false, 'edit succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a non-sender cannot edit a message', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  perform public.delete_message(v_msg);
  select body into v_body from public.messages where id = v_msg;
  execute 'reset role';
  call test_util.record('the sender can soft-delete their message', v_body = '(message deleted)', 'body: ' || v_body);
end $$;

-- ---------------------------------------------------------------------------
-- 9. notification_preferences: own-row only.
do $$
declare v_error text; v_rows int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.notification_preferences (profile_id, email_enabled) values ('55555555-5555-5555-5555-555555555555', true);
  call test_util.record('a user can create their own notification_preferences row', true, 'ok');

  begin
    insert into public.notification_preferences (profile_id, email_enabled) values ('11111111-1111-1111-1111-111111111111', true);
    call test_util.record('a user cannot create a notification_preferences row for someone else', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a user cannot create a notification_preferences row for someone else', true, 'correctly rejected: ' || v_error);
  end;

  select count(*) into v_rows from public.notification_preferences where profile_id <> '55555555-5555-5555-5555-555555555555';
  call test_util.record('a user cannot read anyone else''s notification_preferences', v_rows = 0, 'rows visible: ' || v_rows);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 10. school_messaging_settings: only management can write.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.school_messaging_settings (school_id, email_enabled) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
    call test_util.record('a teacher cannot write school_messaging_settings', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot write school_messaging_settings', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.school_messaging_settings (school_id, email_enabled, sms_enabled)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true, true)
    on conflict (school_id) do update set email_enabled = true, sms_enabled = true;
  call test_util.record('school_owner can write school_messaging_settings', true, 'ok');
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 11. Delivery enqueue: with the school channel enabled AND the recipient's
--     preference enabled, a new notification also creates a pending
--     notification_deliveries row; SMS with no phone on file is 'skipped'.
do $$
declare
  v_conv uuid;
  v_email_status public.message_delivery_status;
  v_sms_status public.message_delivery_status;
  v_deliveries int;
begin
  -- School A email+sms enabled (test 10); guardian 55555555 email pref on (test 9).
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.notification_preferences set sms_enabled = true where profile_id = '55555555-5555-5555-5555-555555555555';
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select (public.start_conversation(array['55555555-5555-5555-5555-555555555555']::uuid[], 'Delivery enqueue test', null, 'direct')).id into v_conv;
  execute 'reset role';

  select status into v_email_status from public.notification_deliveries d
    join public.notifications n on n.id = d.notification_id
    where n.related_entity_id = v_conv and d.recipient_profile_id = '55555555-5555-5555-5555-555555555555' and d.channel = 'email';
  select status into v_sms_status from public.notification_deliveries d
    join public.notifications n on n.id = d.notification_id
    where n.related_entity_id = v_conv and d.recipient_profile_id = '55555555-5555-5555-5555-555555555555' and d.channel = 'sms';

  call test_util.record('an email delivery is enqueued as pending', v_email_status = 'pending', 'status: ' || coalesce(v_email_status::text, 'null'));
  call test_util.record('an sms delivery with no phone on file is skipped', v_sms_status = 'skipped', 'status: ' || coalesce(v_sms_status::text, 'null'));

  -- The teacher (no preferences row, no school override matched) gets no external delivery.
  select count(*) into v_deliveries from public.notification_deliveries d
    join public.notifications n on n.id = d.notification_id
    where n.related_entity_id = v_conv and d.recipient_profile_id = '11111111-1111-1111-1111-111111111111';
  call test_util.record('a recipient with no channel preference gets no external delivery', v_deliveries = 0, 'deliveries: ' || v_deliveries);
end $$;

-- ---------------------------------------------------------------------------
-- 12. A recipient can see the delivery status of their own notifications
--     but not anyone else's.
do $$
declare v_mine int; v_others int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_mine from public.notification_deliveries where recipient_profile_id = '55555555-5555-5555-5555-555555555555';
  select count(*) into v_others from public.notification_deliveries where recipient_profile_id <> '55555555-5555-5555-5555-555555555555';
  execute 'reset role';
  call test_util.record('a recipient sees their own notification_deliveries', v_mine >= 1, 'mine: ' || v_mine);
  call test_util.record('a recipient cannot see other recipients'' notification_deliveries', v_others = 0, 'others: ' || v_others);
end $$;

-- ---------------------------------------------------------------------------
-- 13. A guardian-visible behaviour incident notifies the learner's guardians;
--     a staff-only one does not.
do $$
declare
  v_incident uuid;
  v_notif_5555 int;
  v_notif_5959 int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, description, guardian_visible)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            (select id from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' order by start_date desc limit 1),
            'positive', 'Helped a classmate.', true)
    returning id into v_incident;
  execute 'reset role';

  select count(*) into v_notif_5555 from public.notifications
    where recipient_profile_id = '55555555-5555-5555-5555-555555555555' and type = 'behaviour_incident' and related_entity_id = v_incident;
  select count(*) into v_notif_5959 from public.notifications
    where recipient_profile_id = '59595959-5959-5959-5959-595959595959' and type = 'behaviour_incident' and related_entity_id = v_incident;

  call test_util.record('a guardian-visible behaviour incident notifies guardian 55555555', v_notif_5555 = 1, 'notifs: ' || v_notif_5555);
  call test_util.record('a guardian-visible behaviour incident notifies guardian 59595959', v_notif_5959 = 1, 'notifs: ' || v_notif_5959);
end $$;

do $$
declare
  v_incident uuid;
  v_notif int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, description, guardian_visible)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            (select id from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' order by start_date desc limit 1),
            'negative', 'Internal note only.', false)
    returning id into v_incident;
  execute 'reset role';

  select count(*) into v_notif from public.notifications
    where recipient_profile_id = '55555555-5555-5555-5555-555555555555' and type = 'behaviour_incident' and related_entity_id = v_incident;
  call test_util.record('a staff-only behaviour incident does not notify guardians', v_notif = 0, 'notifs: ' || v_notif);
end $$;
