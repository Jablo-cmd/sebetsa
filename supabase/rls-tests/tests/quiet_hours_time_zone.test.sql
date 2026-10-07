-- Quiet hours in the recipient's IANA time zone: midnight crossing, DST, fallback chain, multi-zone. Rolled back.
begin;

create or replace function pg_temp.rel(p_now text, p_start time, p_end time, p_tz text) returns text
language sql as $$ select (public.quiet_hours_release(p_now::timestamptz, p_start, p_end, p_tz) at time zone 'UTC')::text $$;

do $$
declare
  r text;
begin
  -- Same instant, different zones: 21:30 UTC is 23:30 in Johannesburg (inside 22:00-06:00), 17:30 in New York (outside).
  r := pg_temp.rel('2026-06-10 21:30:00+00', '22:00', '06:00', 'Africa/Johannesburg');
  if r is distinct from '2026-06-11 04:00:00' then raise exception 'FAIL: Johannesburg release %, expected 04:00 UTC next day', r; end if;
  if pg_temp.rel('2026-06-10 21:30:00+00', '22:00', '06:00', 'America/New_York') is not null then raise exception 'FAIL: New York should not be quiet'; end if;
  -- Asia/Kolkata (+05:30): 00:30 UTC is 06:00 local = window end => not quiet; 00:29 UTC is 05:59 => quiet until 00:30 UTC.
  if pg_temp.rel('2026-06-10 00:30:00+00', '22:00', '06:00', 'Asia/Kolkata') is not null then raise exception 'FAIL: Kolkata window end is exclusive'; end if;
  r := pg_temp.rel('2026-06-10 00:29:00+00', '22:00', '06:00', 'Asia/Kolkata');
  if r is distinct from '2026-06-10 00:30:00' then raise exception 'FAIL: Kolkata release %', r; end if;
  raise notice 'PASS: quiet hours follow the recipient zone, including half-hour offsets';
end $$;

do $$
declare r text;
begin
  -- Midnight crossing: before and after midnight local both defer to 06:00 local.
  r := pg_temp.rel('2026-06-10 23:00:00+00', '22:00', '06:00', 'UTC');
  if r is distinct from '2026-06-11 06:00:00' then raise exception 'FAIL: late-evening release %', r; end if;
  r := pg_temp.rel('2026-06-10 03:00:00+00', '22:00', '06:00', 'UTC');
  if r is distinct from '2026-06-10 06:00:00' then raise exception 'FAIL: early-morning release %', r; end if;
  -- Same-day window.
  r := pg_temp.rel('2026-06-10 13:00:00+00', '12:00', '14:00', 'UTC');
  if r is distinct from '2026-06-10 14:00:00' then raise exception 'FAIL: same-day release %', r; end if;
  if pg_temp.rel('2026-06-10 15:00:00+00', '12:00', '14:00', 'UTC') is not null then raise exception 'FAIL: outside same-day window'; end if;
  -- Degenerate windows never defer.
  if pg_temp.rel('2026-06-10 03:00:00+00', '22:00', '22:00', 'UTC') is not null or pg_temp.rel('2026-06-10 03:00:00+00', null, '06:00', 'UTC') is not null then
    raise exception 'FAIL: degenerate window deferred';
  end if;
  raise notice 'PASS: midnight-crossing, same-day and degenerate windows';
end $$;

do $$
declare r text;
begin
  -- DST (Europe/London): clocks go forward 2026-03-29 01:00 UTC. 22:00-06:00 local on the night of 28->29 March:
  -- 23:30 UTC on the 28th is 23:30 GMT; the window ends at 06:00 BST = 05:00 UTC (not 06:00 UTC).
  r := pg_temp.rel('2026-03-28 23:30:00+00', '22:00', '06:00', 'Europe/London');
  if r is distinct from '2026-03-29 05:00:00' then raise exception 'FAIL: spring-forward release % (expected 05:00 UTC)', r; end if;
  -- Clocks go back 2026-10-25 01:00 UTC: the window ends at 06:00 GMT = 06:00 UTC.
  r := pg_temp.rel('2026-10-24 23:30:00+00', '22:00', '06:00', 'Europe/London');
  if r is distinct from '2026-10-25 06:00:00' then raise exception 'FAIL: fall-back release % (expected 06:00 UTC)', r; end if;
  -- A window end that does not exist (America/New_York, 2026-03-08 02:30 is skipped) still releases after now and within hours.
  r := pg_temp.rel('2026-03-08 05:00:00+00', '22:00', '02:30', 'America/New_York');
  if r is null or r::timestamp <= '2026-03-08 05:00:00' or r::timestamp > '2026-03-08 09:00:00' then raise exception 'FAIL: nonexistent local end released at %', r; end if;
  raise notice 'PASS: daylight-saving transitions move the release correctly';
end $$;

do $$
begin
  -- Unknown zone falls back to UTC rather than failing.
  if pg_temp.rel('2026-06-10 23:00:00+00', '22:00', '06:00', 'Mars/Olympus') is distinct from '2026-06-11 06:00:00' then raise exception 'FAIL: bad zone fallback'; end if;
  if pg_temp.rel('2026-06-10 23:00:00+00', '22:00', '06:00', null) is distinct from '2026-06-11 06:00:00' then raise exception 'FAIL: null zone fallback'; end if;
  raise notice 'PASS: unknown or missing zone falls back to UTC';
end $$;

-- End to end: the trigger uses user zone, then organisation zone, then UTC; deliveries are scheduled accordingly.
insert into public.organizations (id, name, status, timezone) values
  ('00000000-0000-0000-0000-0000000f1001', 'Org Tokyo', 'active', 'Asia/Tokyo'),
  ('00000000-0000-0000-0000-0000000f1002', 'Org Lima', 'active', 'America/Lima');
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', ('00000000-0000-0000-0000-0000000f11' || lpad(i::text, 2, '0'))::uuid, 'authenticated', 'authenticated',
       'qh' || i || '@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()
from generate_series(1, 3) i;
insert into public.profiles (id, tenant_id, first_name, last_name, email, phone, role, status) values
  ('00000000-0000-0000-0000-0000000f1101', '00000000-0000-0000-0000-0000000f1001', 'A', 'One', 'qh1@example.com', '+810000001', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f1102', '00000000-0000-0000-0000-0000000f1001', 'B', 'Two', 'qh2@example.com', '+810000002', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000f1103', '00000000-0000-0000-0000-0000000f1002', 'C', 'Three', 'qh3@example.com', '+510000003', 'employee', 'active');
-- A: explicit zone New York; B: no zone (uses org Tokyo); C: invalid-looking is impossible to store, so none (org Lima).
insert into public.notification_preferences (profile_id, email_enabled, quiet_hours_start, quiet_hours_end, time_zone) values
  ('00000000-0000-0000-0000-0000000f1101', true, '00:00', '23:59', 'America/New_York'),
  ('00000000-0000-0000-0000-0000000f1102', true, '00:00', '23:59', null),
  ('00000000-0000-0000-0000-0000000f1103', true, '00:00', '23:59', null);

do $$
declare v_id uuid; a timestamptz; b timestamptz; c timestamptz;
begin
  -- 00:00-23:59 is "quiet" almost all day in every zone: the release is the local 23:59 of today (or tomorrow if just past it).
  insert into public.notifications (id, tenant_id, recipient_profile_id, type, title, body) values (gen_random_uuid(), '00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f1101', 't', 't', 'b') returning id into v_id;
  select scheduled_for into a from public.notification_deliveries where notification_id = v_id and channel = 'email';
  insert into public.notifications (id, tenant_id, recipient_profile_id, type, title, body) values (gen_random_uuid(), '00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f1102', 't', 't', 'b') returning id into v_id;
  select scheduled_for into b from public.notification_deliveries where notification_id = v_id and channel = 'email';
  insert into public.notifications (id, tenant_id, recipient_profile_id, type, title, body) values (gen_random_uuid(), '00000000-0000-0000-0000-0000000f1002', '00000000-0000-0000-0000-0000000f1103', 't', 't', 'b') returning id into v_id;
  select scheduled_for into c from public.notification_deliveries where notification_id = v_id and channel = 'email';

  if a is null or b is null or c is null then raise exception 'FAIL: deliveries not enqueued'; end if;
  if (a at time zone 'America/New_York')::time <> '23:59' then raise exception 'FAIL: user zone not used: %', a at time zone 'America/New_York'; end if;
  if (b at time zone 'Asia/Tokyo')::time <> '23:59' then raise exception 'FAIL: organisation zone not used as fallback: %', b at time zone 'Asia/Tokyo'; end if;
  if (c at time zone 'America/Lima')::time <> '23:59' then raise exception 'FAIL: second organisation zone not used: %', c at time zone 'America/Lima'; end if;
  raise notice 'PASS: deliveries are scheduled in the user zone, falling back to the organisation zone';
end $$;

do $$
begin
  begin
    update public.notification_preferences set time_zone = 'Not/AZone' where profile_id = '00000000-0000-0000-0000-0000000f1101';
    raise exception 'FAIL: invalid zone accepted';
  exception when sqlstate '22023' then null;
  end;
  update public.notification_preferences set time_zone = 'Africa/Maputo' where profile_id = '00000000-0000-0000-0000-0000000f1101';
  raise notice 'PASS: unknown zones are rejected, IANA names accepted';
end $$;

rollback;
