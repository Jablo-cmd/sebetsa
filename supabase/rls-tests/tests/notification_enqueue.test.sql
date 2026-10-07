-- External delivery producer: notifications enqueue one outbox row per opted-in
-- channel, only for active recipients with a destination, deferred by quiet hours.

begin;

insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-0000000f0501', 'Org K', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, crypt('x', gen_salt('bf')), now(), jsonb_build_object('role', 'employee'), '{}', now(), now()
from (values
  ('00000000-0000-0000-0000-0000000f0511', 'all-k@example.com'),
  ('00000000-0000-0000-0000-0000000f0512', 'none-k@example.com'),
  ('00000000-0000-0000-0000-0000000f0513', 'nophone-k@example.com'),
  ('00000000-0000-0000-0000-0000000f0514', 'inactive-k@example.com'),
  ('00000000-0000-0000-0000-0000000f0515', 'quiet-k@example.com')
) as u(id, email);

insert into public.profiles (id, tenant_id, first_name, last_name, email, phone, role, status) values
  ('00000000-0000-0000-0000-0000000f0511', '00000000-0000-0000-0000-0000000f0501', 'All', 'K', 'all-k@example.com', '+27000000001', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0512', '00000000-0000-0000-0000-0000000f0501', 'None', 'K', 'none-k@example.com', '+27000000002', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0513', '00000000-0000-0000-0000-0000000f0501', 'NoPhone', 'K', 'nophone-k@example.com', null, 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0514', '00000000-0000-0000-0000-0000000f0501', 'Inactive', 'K', 'inactive-k@example.com', '+27000000004', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f0515', '00000000-0000-0000-0000-0000000f0501', 'Quiet', 'K', 'quiet-k@example.com', '+27000000005', 'employee', 'active');

insert into public.notification_preferences (profile_id, email_enabled, sms_enabled, whatsapp_enabled, quiet_hours_start, quiet_hours_end) values
  ('00000000-0000-0000-0000-0000000f0511', true, true, true, null, null),
  ('00000000-0000-0000-0000-0000000f0513', true, true, true, null, null),
  ('00000000-0000-0000-0000-0000000f0514', true, true, true, null, null),
  -- A window covering "now" in UTC whichever minute the suite runs (overnight form).
  ('00000000-0000-0000-0000-0000000f0515', true, false, false,
     ((now() at time zone 'utc')::time - interval '1 hour')::time, ((now() at time zone 'utc')::time + interval '2 hours')::time);

update public.profiles set status = 'inactive' where id = '00000000-0000-0000-0000-0000000f0514';

do $$
declare
  v_n public.notifications;
  v_count int;
  v_channels text[];
  v_sched timestamptz;
begin
  -- Opted into everything: one row per channel, with the right destination.
  v_n := public.create_notification('00000000-0000-0000-0000-0000000f0511', 'task_assigned', 'T', 'B', '00000000-0000-0000-0000-0000000f0501');
  select array_agg(channel order by channel) into v_channels from public.notification_deliveries where notification_id = v_n.id;
  if v_channels <> array['email','sms','whatsapp'] then raise exception 'FAIL: expected email,sms,whatsapp, got %', v_channels; end if;
  if (select destination from public.notification_deliveries where notification_id = v_n.id and channel = 'email') <> 'all-k@example.com' then raise exception 'FAIL: wrong email destination'; end if;
  if (select destination from public.notification_deliveries where notification_id = v_n.id and channel = 'sms') <> '+27000000001' then raise exception 'FAIL: wrong sms destination'; end if;
  if (select status from public.notification_deliveries where notification_id = v_n.id and channel = 'email') <> 'pending' then raise exception 'FAIL: new delivery must be pending'; end if;

  -- Idempotent: re-running the enqueue for the same notification adds nothing.
  insert into public.notification_deliveries (notification_id, recipient_profile_id, channel, destination)
  values (v_n.id, v_n.recipient_profile_id, 'email', 'dup@example.com') on conflict (notification_id, channel) do nothing;
  select count(*) into v_count from public.notification_deliveries where notification_id = v_n.id;
  if v_count <> 3 then raise exception 'FAIL: duplicate delivery for a channel (count %)', v_count; end if;

  -- No preferences row: in-app only.
  v_n := public.create_notification('00000000-0000-0000-0000-0000000f0512', 'task_assigned', 'T', 'B', '00000000-0000-0000-0000-0000000f0501');
  select count(*) into v_count from public.notification_deliveries where notification_id = v_n.id;
  if v_count <> 0 then raise exception 'FAIL: a user with no preferences must get in-app only, got % deliveries', v_count; end if;

  -- No phone number: phone channels are not queued, email is.
  v_n := public.create_notification('00000000-0000-0000-0000-0000000f0513', 'task_assigned', 'T', 'B', '00000000-0000-0000-0000-0000000f0501');
  select array_agg(channel order by channel) into v_channels from public.notification_deliveries where notification_id = v_n.id;
  if v_channels <> array['email'] then raise exception 'FAIL: without a phone only email should be queued, got %', v_channels; end if;

  -- Inactive account: nothing external.
  v_n := public.create_notification('00000000-0000-0000-0000-0000000f0514', 'task_assigned', 'T', 'B', '00000000-0000-0000-0000-0000000f0501');
  select count(*) into v_count from public.notification_deliveries where notification_id = v_n.id;
  if v_count <> 0 then raise exception 'FAIL: an inactive account must not receive external messages, got %', v_count; end if;

  -- Quiet hours defer the send to the end of the window (and never into the past).
  v_n := public.create_notification('00000000-0000-0000-0000-0000000f0515', 'task_assigned', 'T', 'B', '00000000-0000-0000-0000-0000000f0501');
  select scheduled_for into v_sched from public.notification_deliveries where notification_id = v_n.id and channel = 'email';
  if v_sched is null or v_sched <= now() + interval '1 hour' or v_sched > now() + interval '2 hours 1 minute' then
    raise exception 'FAIL: quiet hours should defer to ~2h from now, got % (now %)', v_sched, now();
  end if;

  raise notice 'PASS: notifications enqueue one delivery per opted-in channel, honouring status, destination and quiet hours';
end $$;

-- The outbox stays invisible to other users.
set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0512","app_metadata":{"role":"employee"}}';
do $$
declare v_count int;
begin
  select count(*) into v_count from public.notification_deliveries;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: a user can see other users'' deliveries (%)', v_count; end if;
  raise notice 'PASS: users only see their own deliveries';
end $$;

rollback;
