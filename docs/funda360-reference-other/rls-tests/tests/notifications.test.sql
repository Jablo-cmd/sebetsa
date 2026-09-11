-- Regression suite for the Notification Engine foundation (FND-COM-001,
-- 20260829100000_notifications.sql). Reuses School A/B fixtures:
-- School A id aaaaaaaa-...-aaaaaaaaaaaa / school_owner 22222222-...-2222,
-- School B id bbbbbbbb-...-bbbbbbbbbbbb, teacher 11111111-...-11111111.
--
-- Creates its own dedicated guardian profile (never reused/mutated by any
-- other test file) as the send_guardian_invitation() target.

do $$
begin
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data) values
    ('00000000-0000-0000-0000-000000000000', '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b',
     'authenticated', 'authenticated', 'notif-guardian@schoola.test',
     jsonb_build_object('role', 'guardian', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
  insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
    ('9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Notif', 'Guardian', 'notif-guardian@schoola.test', 'guardian', 'active');
end $$;

-- ---------------------------------------------------------------------------
-- 1. send_guardian_invitation() (school_owner, authorized) creates exactly
-- one real in-app notification for the invited guardian, with the correct
-- recipient, type, and link_path — not a demo stub.
do $$
declare v_count int;
declare v_link text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  perform public.send_guardian_invitation('9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 72);
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.notifications
    where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b' and type = 'guardian_invitation';
  select link_path into v_link from public.notifications
    where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b' and type = 'guardian_invitation';
  execute 'reset role';

  call test_util.record('send_guardian_invitation creates exactly one real notification for the guardian', v_count = 1, 'rows: ' || v_count);
  call test_util.record('the notification carries the correct link_path', v_link = '/activate-account', 'link_path=' || coalesce(v_link, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. The recipient guardian can see their own notification (asserted above
-- implicitly by the successful select — this makes the RLS grant explicit
-- and independently named).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.notifications where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b';
  execute 'reset role';
  call test_util.record('a guardian can view their own notifications', v_count >= 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Nobody else can see that guardian's notification — not another
-- guardian, not a staff member of the same school, not even the
-- school_owner who triggered it (notifications are personal, unlike
-- audit_log which is administrative).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.notifications where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b';
  execute 'reset role';
  call test_util.record('a teacher (not the recipient) cannot see another user''s notification', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.notifications where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b';
  execute 'reset role';
  call test_util.record('even the school_owner who triggered it cannot see the guardian''s own notification', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant: School B cannot see this at all (belt-and-braces on top
-- of the recipient-only policy already proven above).
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('16161616-1616-1616-1616-161616161616', 'finance_manager', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.notifications where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b';
  execute 'reset role';
  call test_util.record('School B staff cannot see School A''s notification', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. The recipient can mark their own notification read (read_at moves
-- from NULL to a real timestamp).
do $$
declare v_notification_id uuid;
declare v_read_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select id into v_notification_id from public.notifications where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b' and type = 'guardian_invitation';
  update public.notifications set read_at = now() where id = v_notification_id;
  select read_at into v_read_at from public.notifications where id = v_notification_id;
  execute 'reset role';
  call test_util.record('the recipient can mark their own notification read', v_read_at is not null, 'read_at=' || coalesce(v_read_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 6. Nobody else can mark it read on the recipient's behalf.
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.notifications set read_at = now() where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b' and read_at is null;
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('nobody but the recipient can update their notification', v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 7. No authenticated caller can insert a notification directly — only
-- create_notification() (called from inside another SECURITY DEFINER
-- function's body) can.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.notifications (school_id, recipient_profile_id, type, title, body)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 'forged', 'Forged', 'A client should never be able to write this directly.');
    call test_util.record('a client cannot insert a notification directly', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a client cannot insert a notification directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 8. Hard delete is impossible even for the recipient (no DELETE policy).
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.notifications where recipient_profile_id = '9b9b9b9b-9b9b-9b9b-9b9b-9b9b9b9b9b9b';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a notification is impossible even for its own recipient', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
