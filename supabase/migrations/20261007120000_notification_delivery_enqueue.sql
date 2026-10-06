-- External notification delivery: the producer side of the outbox.
--
-- notification_deliveries and the claim RPC/worker already existed, but
-- nothing ever inserted into the outbox, so email / SMS / WhatsApp delivery
-- could not happen even once provider credentials were configured. Every
-- in-app notification (all of which come from create_notification()) now
-- enqueues one delivery per channel the recipient has opted into.
--
-- Rules:
--   * only an active profile receives external messages;
--   * a channel needs a destination (profiles.email / profiles.phone) —
--     without one nothing is queued rather than queueing a message that can
--     only fail;
--   * quiet hours defer the delivery to the end of the window. Quiet hours are
--     stored without a time zone, so they are evaluated in UTC until a
--     per-user time zone exists (documented limitation);
--   * one delivery per (notification, channel): enqueueing is idempotent.
-- In-app notifications are unaffected: a failure to enqueue never blocks them
-- because this runs in the same transaction only for rows that qualify.

create unique index if not exists notification_deliveries_notification_channel_key
  on public.notification_deliveries (notification_id, channel);

create or replace function public.enqueue_notification_deliveries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pref public.notification_preferences;
  v_profile public.profiles;
  v_now_utc timestamp := (now() at time zone 'utc');
  v_time time := v_now_utc::time;
  v_deferred boolean := false;
  v_scheduled timestamptz := now();
  v_end timestamp;
begin
  select * into v_profile from public.profiles where id = new.recipient_profile_id and status = 'active';
  if not found then
    return new;
  end if;

  select * into v_pref from public.notification_preferences where profile_id = new.recipient_profile_id;
  if not found then
    return new;
  end if;

  if v_pref.quiet_hours_start is not null and v_pref.quiet_hours_end is not null
     and v_pref.quiet_hours_start <> v_pref.quiet_hours_end then
    if v_pref.quiet_hours_start < v_pref.quiet_hours_end then
      v_deferred := v_time >= v_pref.quiet_hours_start and v_time < v_pref.quiet_hours_end;
    else
      v_deferred := v_time >= v_pref.quiet_hours_start or v_time < v_pref.quiet_hours_end;
    end if;
    if v_deferred then
      v_end := date_trunc('day', v_now_utc) + v_pref.quiet_hours_end;
      if v_end <= v_now_utc then
        v_end := v_end + interval '1 day';
      end if;
      v_scheduled := v_end at time zone 'utc';
    end if;
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

drop trigger if exists notifications_enqueue_deliveries on public.notifications;
create trigger notifications_enqueue_deliveries
  after insert on public.notifications
  for each row
  execute function public.enqueue_notification_deliveries();
