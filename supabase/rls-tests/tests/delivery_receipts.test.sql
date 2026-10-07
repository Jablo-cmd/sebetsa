-- Provider delivery receipts: idempotent, monotonic, channel-matched, reconcilable, service-role only, and they never touch
-- the outbox's own state (status / lease / worker / attempts). One transaction, rolled back.
begin;

insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-0000000f2001', 'Org Receipts', 'active');
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000f2101', 'authenticated', 'authenticated', 'rcpt@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, phone, role, status)
values ('00000000-0000-0000-0000-0000000f2101', '00000000-0000-0000-0000-0000000f2001', 'R', 'One', 'rcpt@example.com', '+27000000099', 'employee', 'active');
insert into public.notification_preferences (profile_id, email_enabled, sms_enabled) values ('00000000-0000-0000-0000-0000000f2101', true, true);
insert into public.notifications (id, tenant_id, recipient_profile_id, type, title, body)
values ('00000000-0000-0000-0000-0000000f2201', '00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f2101', 't', 't', 'b');

-- Simulate the dispatcher having sent both: record provider ids, leave the claim state as the worker leaves it.
update public.notification_deliveries set status = 'sent', sent_at = now(), attempts = 1, worker_id = null,
       provider_message_id = case channel when 'email' then 'resend-msg-1' else 'SMtwilio1' end
 where notification_id = '00000000-0000-0000-0000-0000000f2201';

create temp table before_state as
select id, status, attempts, worker_id, claimed_at, claim_expires_at, scheduled_for from public.notification_deliveries
 where notification_id = '00000000-0000-0000-0000-0000000f2201';

set local role service_role;

do $$
declare r text; d public.notification_deliveries;
begin
  r := public.record_delivery_receipt('resend', 'evt-1', 'resend-msg-1', 'accepted', now() - interval '3 minutes');
  if r <> 'applied' then raise exception 'FAIL: first receipt %', r; end if;
  r := public.record_delivery_receipt('resend', 'evt-2', 'resend-msg-1', 'delivered', now() - interval '2 minutes');
  if r <> 'applied' then raise exception 'FAIL: delivered receipt %', r; end if;
  select * into d from public.notification_deliveries where provider_message_id = 'resend-msg-1';
  if d.provider_status <> 'delivered' or d.delivered_at is null or d.provider <> 'resend' then raise exception 'FAIL: delivery not updated: %', d.provider_status; end if;
  raise notice 'PASS: receipts update provider status and delivered_at';
end $$;

do $$
declare r text; d public.notification_deliveries; n int;
begin
  -- Replay of the same event: duplicate, no second event row.
  r := public.record_delivery_receipt('resend', 'evt-2', 'resend-msg-1', 'delivered', now());
  if r <> 'duplicate' then raise exception 'FAIL: replay not detected: %', r; end if;
  select count(*) into n from public.notification_delivery_events where provider_event_id = 'evt-2';
  if n <> 1 then raise exception 'FAIL: replay stored twice'; end if;
  -- Out-of-order older status does not regress.
  r := public.record_delivery_receipt('resend', 'evt-3', 'resend-msg-1', 'sent', now() - interval '10 minutes');
  select * into d from public.notification_deliveries where provider_message_id = 'resend-msg-1';
  if d.provider_status <> 'delivered' then raise exception 'FAIL: status regressed to %', d.provider_status; end if;
  -- A later bounce is applied and recorded with its error.
  r := public.record_delivery_receipt('resend', 'evt-4', 'resend-msg-1', 'bounced', now(), 'mailbox full');
  select * into d from public.notification_deliveries where provider_message_id = 'resend-msg-1';
  if d.provider_status <> 'bounced' or d.provider_error <> 'mailbox full' then raise exception 'FAIL: bounce not recorded'; end if;
  raise notice 'PASS: replays are idempotent, status is monotonic, failures keep their reason';
end $$;

do $$
declare r text; d public.notification_deliveries;
begin
  -- A receipt from the wrong provider for a channel never matches (a Resend id cannot update an SMS delivery).
  r := public.record_delivery_receipt('resend', 'evt-x', 'SMtwilio1', 'delivered', now());
  if r <> 'unmatched' then raise exception 'FAIL: cross-channel receipt matched: %', r; end if;
  r := public.record_delivery_receipt('twilio', 'SMtwilio1:delivered', 'SMtwilio1', 'delivered', now());
  if r <> 'applied' then raise exception 'FAIL: twilio receipt %', r; end if;
  -- Unknown message id: stored, unmatched.
  r := public.record_delivery_receipt('twilio', 'SMlater:delivered', 'SMlater', 'delivered', now());
  if r <> 'unmatched' then raise exception 'FAIL: unknown message should be unmatched, got %', r; end if;
  raise notice 'PASS: receipts only match their own provider and channel; unknown ids are kept unmatched';
end $$;

do $$
declare n int; d public.notification_deliveries; j jsonb;
begin
  -- The dispatcher later learns the id; the scheduled job applies the early receipt.
  reset role;
  update public.notification_deliveries set provider_message_id = 'SMlater' where provider_message_id = 'SMtwilio1';
  set local role service_role;
  j := public.run_scheduled_job('reconcile_receipts');
  if j->>'status' <> 'succeeded' then raise exception 'FAIL: job %', j; end if;
  select * into d from public.notification_deliveries where provider_message_id = 'SMlater';
  if d.provider_status <> 'delivered' then raise exception 'FAIL: early receipt not reconciled (%)', d.provider_status; end if;
  select count(*) into n from public.notification_delivery_events where not applied and provider_event_id = 'SMlater:delivered';
  if n <> 0 then raise exception 'FAIL: event still unapplied'; end if;
  raise notice 'PASS: early receipts are reconciled by the scheduled job';
end $$;

do $$
declare n int; h jsonb;
begin
  -- The outbox's own state is exactly as the worker left it (compared as the table owner; the temp table is not service_role's).
  reset role;
  select count(*) into n from public.notification_deliveries d join before_state b using (id)
   where d.status is distinct from b.status or d.attempts is distinct from b.attempts or d.worker_id is distinct from b.worker_id
      or d.claimed_at is distinct from b.claimed_at or d.claim_expires_at is distinct from b.claim_expires_at or d.scheduled_for is distinct from b.scheduled_for;
  if n <> 0 then raise exception 'FAIL: receipts altered outbox state on % rows', n; end if;
  set local role service_role;
  -- Failed-delivery visibility for operators.
  h := public.ops_health();
  if (h->'notifications'->>'receipt_failures_24h')::int < 1 then raise exception 'FAIL: bounce not visible in ops_health'; end if;
  raise notice 'PASS: outbox claim/lease/attempt state is untouched and failures are visible to operators';
end $$;

reset role;
do $$
declare v_role text; v_fn text; v_ok boolean;
begin
  foreach v_role in array array['authenticated', 'anon'] loop
    foreach v_fn in array array[
      'select public.record_delivery_receipt(''resend'', ''e'', ''m'', ''delivered'', now())',
      'select public.reconcile_delivery_receipts()',
      'select public.apply_delivery_receipt(gen_random_uuid())',
      'select * from public.notification_delivery_events'] loop
      v_ok := false;
      begin
        execute format('set local role %I', v_role);
        set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f2101","app_metadata":{"role":"employee"}}';
        execute v_fn;
        v_ok := true;
      exception when insufficient_privilege then null;
      end;
      reset role;
      if v_ok then raise exception 'SECURITY_FAILURE: % can run %', v_role, v_fn; end if;
    end loop;
  end loop;
  raise notice 'PASS: receipt functions and the event log are service_role only';
end $$;

rollback;
