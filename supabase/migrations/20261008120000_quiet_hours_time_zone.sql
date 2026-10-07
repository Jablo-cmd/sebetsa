-- Per-user IANA time zone for notification quiet hours.
--
-- Quiet hours were evaluated in UTC. They are now evaluated in the recipient's own zone:
--   1. notification_preferences.time_zone (the user's choice, an IANA name such as 'Africa/Maputo')
--   2. else the organisation's timezone
--   3. else UTC (never an assumed country)
-- A name the database does not know is rejected on write, and ignored (falling through the chain) if it
-- ever reaches the evaluator, so a bad value can delay nothing and break nothing.
-- Midnight-crossing windows (22:00-06:00) and daylight-saving changes are handled by working in local
-- wall-clock time and converting the window end back with the zone's own rules.

alter table public.notification_preferences add column time_zone text;

create or replace function public.is_valid_time_zone(p_name text)
returns boolean
language sql
stable
set search_path = public, pg_catalog
as $$
  select p_name is not null and exists (select 1 from pg_catalog.pg_timezone_names n where n.name = p_name)
$$;

create or replace function public.validate_notification_preference_zone()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.time_zone is not null and not public.is_valid_time_zone(new.time_zone) then
    raise exception 'invalid_parameter: unknown time zone %', left(new.time_zone, 64) using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger notification_preferences_validate_zone
  before insert or update on public.notification_preferences
  for each row execute function public.validate_notification_preference_zone();

-- Returns NULL when `p_now` is outside the quiet window, otherwise the instant the window ends.
create or replace function public.quiet_hours_release(p_now timestamptz, p_start time, p_end time, p_tz text)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  v_zone text := case when public.is_valid_time_zone(p_tz) then p_tz else 'UTC' end;
  v_local timestamp := p_now at time zone v_zone;
  v_time time := v_local::time;
  v_in_window boolean;
  v_end_local timestamp;
  v_release timestamptz;
begin
  if p_start is null or p_end is null or p_start = p_end then
    return null;
  end if;

  if p_start < p_end then
    v_in_window := v_time >= p_start and v_time < p_end;
    v_end_local := date_trunc('day', v_local) + p_end;
  else
    v_in_window := v_time >= p_start or v_time < p_end;
    v_end_local := date_trunc('day', v_local) + p_end + case when v_time >= p_start then interval '1 day' else interval '0' end;
  end if;

  if not v_in_window then
    return null;
  end if;

  v_release := v_end_local at time zone v_zone;
  -- A DST fold/gap can only ever move the release by the transition size; never release in the past.
  if v_release <= p_now then
    v_release := p_now + interval '1 minute';
  end if;
  return v_release;
end;
$$;

create or replace function public.enqueue_notification_deliveries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pref public.notification_preferences;
  v_profile public.profiles;
  v_org_zone text;
  v_zone text;
  v_scheduled timestamptz := now();
  v_release timestamptz;
begin
  select * into v_profile from public.profiles where id = new.recipient_profile_id and status = 'active';
  if not found then
    return new;
  end if;

  select * into v_pref from public.notification_preferences where profile_id = new.recipient_profile_id;
  if not found then
    return new;
  end if;

  select o.timezone into v_org_zone from public.organizations o where o.id = v_profile.tenant_id;
  v_zone := case
    when public.is_valid_time_zone(v_pref.time_zone) then v_pref.time_zone
    when public.is_valid_time_zone(v_org_zone) then v_org_zone
    else 'UTC'
  end;

  v_release := public.quiet_hours_release(now(), v_pref.quiet_hours_start, v_pref.quiet_hours_end, v_zone);
  if v_release is not null then
    v_scheduled := v_release;
  end if;

  if v_pref.email_enabled and coalesce(btrim(v_profile.email), '') <> '' then
    insert into public.notification_deliveries (notification_id, recipient_profile_id, channel, destination, scheduled_for)
    values (new.id, new.recipient_profile_id, 'email', btrim(v_profile.email), v_scheduled)
    on conflict (notification_id, channel) do nothing;
  end if;
  if v_pref.sms_enabled and coalesce(btrim(v_profile.phone), '') <> '' then
    insert into public.notification_deliveries (notification_id, recipient_profile_id, channel, destination, scheduled_for)
    values (new.id, new.recipient_profile_id, 'sms', btrim(v_profile.phone), v_scheduled)
    on conflict (notification_id, channel) do nothing;
  end if;
  if v_pref.whatsapp_enabled and coalesce(btrim(v_profile.phone), '') <> '' then
    insert into public.notification_deliveries (notification_id, recipient_profile_id, channel, destination, scheduled_for)
    values (new.id, new.recipient_profile_id, 'whatsapp', btrim(v_profile.phone), v_scheduled)
    on conflict (notification_id, channel) do nothing;
  end if;

  return new;
end;
$$;

revoke execute on function public.enqueue_notification_deliveries() from public, anon, authenticated;
revoke execute on function public.quiet_hours_release(timestamptz, time, time, text) from public, anon;
grant execute on function public.quiet_hours_release(timestamptz, time, time, text) to authenticated;
revoke execute on function public.validate_notification_preference_zone() from public, anon, authenticated;
revoke execute on function public.is_valid_time_zone(text) from public, anon;
grant execute on function public.is_valid_time_zone(text) to authenticated;
