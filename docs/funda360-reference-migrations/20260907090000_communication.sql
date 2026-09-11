-- Communication & Notifications domain (1/1) — two-way threaded messaging,
-- per-user notification preferences, and the multi-channel delivery
-- architecture (in-app today; email / SMS / WhatsApp ready to activate when
-- a provider's secrets are supplied).
--
-- WHAT ALREADY EXISTED (extended, never duplicated): `announcements`
-- (one-way broadcast, school_owner/principal -> audience) and
-- `notifications` (in-app inbox, one row per recipient, written only via
-- the SECURITY DEFINER create_notification()). Real producers already
-- exist: guardian invitations, 3-day attendance streak, fee overdue /
-- escalation, document expiry, invoice issued, payment settled, report
-- card published. This migration KEEPS all of that and adds:
--
--   1. THREADED MESSAGING. A `conversations` row with N
--      `conversation_participants` and an append-only `messages` stream
--      (soft-editable / soft-deletable), plus `message_attachments` in a
--      private storage bucket. Direct (2-party) and group. Per-participant
--      read cursor (last_read_at), archive, and mute. All writes go through
--      SECURITY DEFINER RPCs — there is no client-writable message state,
--      same trust boundary as every other domain here. Who may talk to
--      whom is can_message_profile(): staff <-> anyone in the tenant;
--      a guardian only <-> staff (never guardian<->guardian or
--      guardian<->learner).
--
--   2. NOTIFICATION PREFERENCES. One `notification_preferences` row per
--      profile (own-row RLS). In-app is always on and cannot be disabled
--      (it is the system of record); email / SMS / WhatsApp are opt-in per
--      channel, with an optional per-type override map and quiet hours.
--
--   3. DELIVERY ARCHITECTURE. create_notification() now also enqueues one
--      `notification_deliveries` row per enabled external channel
--      (status='pending'). That table is the documented hand-off point for
--      a future worker / Edge Function (`where status='pending' and
--      scheduled_for <= now()` -> call provider -> update to sent/failed),
--      exactly the same "adapter ready, wiring waits for real credentials"
--      shape as the Finance payment gateway
--      (20260903100000_payment_gateway.sql). `school_messaging_settings`
--      holds the per-school non-secret channel config; provider API keys
--      live ONLY in Edge Function env, never in a DB row. Nothing is sent
--      until `supabase/functions/notifications-dispatch` is deployed with
--      those secrets — until then delivery rows accumulate as 'pending' and
--      the in-app notification is unaffected.
--
--   4. NEW PRODUCER: a behaviour incident that staff have marked
--      guardian_visible now notifies the learner's active guardians
--      (mirrors get_guardian_visible_behaviour_incidents()'s own
--      opt-in-only visibility model — an internal-only incident never
--      leaks).
--
-- SECURITY: every new tenant-scoped table is ENABLE + FORCE ROW LEVEL
-- SECURITY, fail-closed. Message / conversation / delivery state is
-- RPC-only (no INSERT/UPDATE/DELETE policy for `authenticated` on
-- messages, conversations, conversation_participants beyond the narrow
-- own-cursor update; none at all on notification_deliveries). Cross-tenant
-- isolation is enforced by school_id + participant checks and validated by
-- *_validate_tenant triggers. Every privileged action writes audit_log.

-- ===========================================================================
-- 0. Enums
-- ===========================================================================

create type public.conversation_kind as enum ('direct', 'group');
create type public.message_delivery_channel as enum ('in_app', 'email', 'sms', 'whatsapp');
create type public.message_delivery_status as enum ('pending', 'sent', 'failed', 'skipped');

-- ===========================================================================
-- 1. notification_preferences — one row per profile, own-row RLS.
-- ===========================================================================

create table public.notification_preferences (
  profile_id        uuid primary key references public.profiles (id) on delete cascade,
  school_id         uuid references public.schools (id) on delete cascade,
  email_enabled     boolean not null default false,
  sms_enabled       boolean not null default false,
  whatsapp_enabled  boolean not null default false,
  -- Per-notification-type override. Shape: { "<type>": { "email": false, "sms": true } }.
  -- A key absent here falls back to the channel toggles above. in_app is
  -- never consulted here — it cannot be turned off.
  type_overrides    jsonb not null default '{}'::jsonb,
  quiet_hours_start time,
  quiet_hours_end   time,
  updated_at        timestamptz not null default now(),
  constraint notification_preferences_type_overrides_is_object
    check (jsonb_typeof(type_overrides) = 'object')
);

comment on table public.notification_preferences is 'Per-user delivery preferences. in_app is always on (it is the system of record) and is deliberately not representable here. email/sms/whatsapp are opt-in. type_overrides lets a user silence or enable a single notification type on a channel without touching the global toggle. Quiet hours only delay external delivery (scheduled_for), never the in-app row.';
comment on column public.notification_preferences.quiet_hours_start is 'Local (Africa/Johannesburg) wall-clock start of a do-not-disturb window for external channels. NULL start or end = no quiet hours. A window that wraps midnight (start > end) is supported.';

create index notification_preferences_school_id_idx on public.notification_preferences (school_id);

create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function public.set_updated_at();

-- Keep school_id honest (a user cannot claim another tenant's row) and
-- default it from the profile.
create or replace function public.notification_preferences_validate()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_tenant uuid;
begin
  if new.profile_id is distinct from auth.uid() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: a notification_preferences row belongs to its own profile';
  end if;
  select tenant_id into v_tenant from public.profiles where id = new.profile_id;
  new.school_id := v_tenant;
  return new;
end;
$$;
create trigger notification_preferences_validate_trigger
  before insert or update on public.notification_preferences
  for each row execute function public.notification_preferences_validate();

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;

create policy notification_preferences_select_own on public.notification_preferences
  for select to authenticated using (profile_id = auth.uid() or public.is_platform_admin());
create policy notification_preferences_insert_own on public.notification_preferences
  for insert to authenticated with check (profile_id = auth.uid());
create policy notification_preferences_update_own on public.notification_preferences
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
-- No DELETE — a preferences row is upserted, never removed.

-- ===========================================================================
-- 2. school_messaging_settings — per-school non-secret channel config.
-- ===========================================================================

create table public.school_messaging_settings (
  school_id           uuid primary key references public.schools (id) on delete cascade,
  email_enabled       boolean not null default false,
  sms_enabled         boolean not null default false,
  whatsapp_enabled    boolean not null default false,
  email_from_name     text,
  email_reply_to      text check (email_reply_to is null or email_reply_to ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  sms_sender_id       text,
  -- The provider the dispatch worker should use per channel. Informational
  -- only — the worker still needs the matching secret in its own env or it
  -- no-ops. No API keys, tokens, or passwords are ever stored here.
  email_provider      text,
  sms_provider        text,
  whatsapp_provider   text,
  updated_by          uuid references public.profiles (id) on delete set null,
  updated_at          timestamptz not null default now()
);

comment on table public.school_messaging_settings is 'Per-school switch-board for external notification channels. A channel that is disabled here means create_notification() never enqueues a delivery for it, regardless of user preference. Provider API credentials are NEVER stored here — they live only in the notifications-dispatch Edge Function env (see docs/NOTIFICATIONS_DELIVERY.md). Same secret-handling boundary as payment_gateway_configs.';

create trigger school_messaging_settings_set_updated_at
  before update on public.school_messaging_settings
  for each row execute function public.set_updated_at();

create or replace function public.school_messaging_settings_set_updated_by()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_by := auth.uid();
  return new;
end;
$$;
create trigger school_messaging_settings_set_updated_by_trigger
  before insert or update on public.school_messaging_settings
  for each row execute function public.school_messaging_settings_set_updated_by();

alter table public.school_messaging_settings enable row level security;
alter table public.school_messaging_settings force row level security;

-- Readable by any member of the school (the dispatch decision and the
-- settings UI both need it); writable only by can_manage_school().
create policy school_messaging_settings_select on public.school_messaging_settings
  for select to authenticated using (school_id = public.current_tenant_id() or public.is_platform_admin());
create policy school_messaging_settings_insert on public.school_messaging_settings
  for insert to authenticated with check (public.can_manage_school(school_id));
create policy school_messaging_settings_update on public.school_messaging_settings
  for update to authenticated using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

-- ===========================================================================
-- 3. notification_deliveries — the external-channel outbox / hand-off point.
-- ===========================================================================

create table public.notification_deliveries (
  id                   uuid primary key default gen_random_uuid(),
  notification_id      uuid not null references public.notifications (id) on delete cascade,
  school_id            uuid references public.schools (id) on delete cascade,
  recipient_profile_id uuid not null references public.profiles (id) on delete cascade,
  channel              public.message_delivery_channel not null,
  status               public.message_delivery_status not null default 'pending',
  provider             text,
  destination          text,
  provider_message_id  text,
  error                text,
  attempts             integer not null default 0,
  scheduled_for        timestamptz not null default now(),
  sent_at              timestamptz,
  created_at           timestamptz not null default now(),
  constraint notification_deliveries_channel_is_external check (channel <> 'in_app')
);

comment on table public.notification_deliveries is 'One row per (notification, external channel) that create_notification() decided to attempt, based on school_messaging_settings AND the recipient''s notification_preferences. status=''pending'' rows are the queue a future worker drains: `select ... where status = ''pending'' and attempts < 5 and scheduled_for <= now()`, call the provider adapter, update to sent/failed. Nothing drains it today — see docs/NOTIFICATIONS_DELIVERY.md. destination is the resolved email/phone (snapshotted so a later profile edit does not rewrite history).';

create index notification_deliveries_pending_idx on public.notification_deliveries (status, scheduled_for) where status = 'pending';
create index notification_deliveries_notification_idx on public.notification_deliveries (notification_id);
create index notification_deliveries_recipient_idx on public.notification_deliveries (recipient_profile_id);

alter table public.notification_deliveries enable row level security;
alter table public.notification_deliveries force row level security;

-- A recipient may see the delivery status of their own notifications (the
-- inbox can show "also emailed"). Nobody writes this table through RLS —
-- create_notification() inserts it (SECURITY DEFINER, bypasses RLS) and the
-- dispatch worker updates it with the service_role key.
create policy notification_deliveries_select_own on public.notification_deliveries
  for select to authenticated using (recipient_profile_id = auth.uid() or public.is_platform_admin());

-- ===========================================================================
-- 4. Channel resolution + create_notification() extension
-- ===========================================================================

-- Which external channels should a notification of p_type to p_profile_id
-- actually be delivered on? Returns a set of message_delivery_channel.
-- Honours: school_messaging_settings (school kill-switch) AND
-- notification_preferences (global toggle, then per-type override).
create or replace function public.resolve_notification_channels(
  p_profile_id uuid, p_school_id uuid, p_type text
) returns setof public.message_delivery_channel
language plpgsql stable security definer set search_path = public as $$
declare
  v_school record;
  v_pref record;
  v_override jsonb;
begin
  if p_school_id is null then return; end if;
  select email_enabled, sms_enabled, whatsapp_enabled into v_school
    from public.school_messaging_settings where school_id = p_school_id;
  if not found then return; end if;

  select email_enabled, sms_enabled, whatsapp_enabled, type_overrides into v_pref
    from public.notification_preferences where profile_id = p_profile_id;

  v_override := coalesce(v_pref.type_overrides -> p_type, '{}'::jsonb);

  if coalesce(v_school.email_enabled, false)
     and coalesce((v_override ->> 'email')::boolean, v_pref.email_enabled, false) then
    return next 'email';
  end if;
  if coalesce(v_school.sms_enabled, false)
     and coalesce((v_override ->> 'sms')::boolean, v_pref.sms_enabled, false) then
    return next 'sms';
  end if;
  if coalesce(v_school.whatsapp_enabled, false)
     and coalesce((v_override ->> 'whatsapp')::boolean, v_pref.whatsapp_enabled, false) then
    return next 'whatsapp';
  end if;
  return;
end;
$$;
revoke execute on function public.resolve_notification_channels(uuid, uuid, text) from public;

-- Compute scheduled_for: now(), unless the recipient set quiet hours and we
-- are currently inside them, in which case the next end-of-quiet-hours.
create or replace function public.notification_delivery_schedule(p_profile_id uuid)
returns timestamptz language plpgsql stable security definer set search_path = public as $$
declare
  v_start time; v_end time; v_local timestamptz; v_now_t time; v_today date;
begin
  select quiet_hours_start, quiet_hours_end into v_start, v_end
    from public.notification_preferences where profile_id = p_profile_id;
  if v_start is null or v_end is null or v_start = v_end then
    return now();
  end if;
  v_local := now() at time zone 'Africa/Johannesburg';
  v_now_t := v_local::time;
  v_today := v_local::date;
  if v_start < v_end then
    -- simple window within one day
    if v_now_t >= v_start and v_now_t < v_end then
      return (v_today + v_end) at time zone 'Africa/Johannesburg';
    end if;
  else
    -- window wraps midnight
    if v_now_t >= v_start then
      return ((v_today + 1) + v_end) at time zone 'Africa/Johannesburg';
    elsif v_now_t < v_end then
      return (v_today + v_end) at time zone 'Africa/Johannesburg';
    end if;
  end if;
  return now();
end;
$$;
revoke execute on function public.notification_delivery_schedule(uuid) from public;

-- Enqueue external deliveries for one already-created notification.
create or replace function public.enqueue_notification_deliveries(p_notification_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_n public.notifications;
  v_channel public.message_delivery_channel;
  v_dest text;
  v_schedule timestamptz;
begin
  select * into v_n from public.notifications where id = p_notification_id;
  if not found or v_n.school_id is null then return; end if;

  v_schedule := public.notification_delivery_schedule(v_n.recipient_profile_id);

  for v_channel in
    select public.resolve_notification_channels(v_n.recipient_profile_id, v_n.school_id, v_n.type)
  loop
    if v_channel = 'email' then
      select email into v_dest from public.profiles where id = v_n.recipient_profile_id;
    else
      select phone into v_dest from public.profiles where id = v_n.recipient_profile_id;
    end if;

    insert into public.notification_deliveries (
      notification_id, school_id, recipient_profile_id, channel, destination, status, scheduled_for
    ) values (
      v_n.id, v_n.school_id, v_n.recipient_profile_id, v_channel, v_dest,
      (case when v_dest is null or char_length(trim(v_dest)) = 0 then 'skipped' else 'pending' end)::public.message_delivery_status,
      v_schedule
    );
  end loop;
end;
$$;
revoke execute on function public.enqueue_notification_deliveries(uuid) from public;

-- Re-declare create_notification() with its exact prior body
-- (20260829100000_notifications.sql) plus one added call — that migration
-- file is untouched. Same "extend the sole write path in place" move
-- announcements already made with send_guardian_invitation().
create or replace function public.create_notification(
  p_recipient_profile_id  uuid,
  p_type                  text,
  p_title                 text,
  p_body                  text,
  p_school_id             uuid default null,
  p_related_entity_table  text default null,
  p_related_entity_id     uuid default null,
  p_link_path             text default null
) returns public.notifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result public.notifications;
begin
  insert into public.notifications (
    school_id, recipient_profile_id, type, title, body, related_entity_table, related_entity_id, link_path
  ) values (
    p_school_id, p_recipient_profile_id, p_type, p_title, p_body, p_related_entity_table, p_related_entity_id, p_link_path
  )
  returning * into v_result;

  perform public.enqueue_notification_deliveries(v_result.id);

  return v_result;
end;
$$;

revoke execute on function public.create_notification(uuid, text, text, text, uuid, text, uuid, text) from public;

-- ===========================================================================
-- 5. Messaging — conversations, participants, messages, attachments
-- ===========================================================================

create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null references public.schools (id) on delete cascade,
  kind            public.conversation_kind not null default 'direct',
  subject         text,
  created_by      uuid references public.profiles (id) on delete set null,
  last_message_at timestamptz not null default now(),
  message_count   integer not null default 0,
  created_at      timestamptz not null default now()
);

comment on table public.conversations is 'A message thread between 2 (kind=direct) or more (kind=group) profiles in one school. Created only via start_conversation(). A direct conversation between the same two people is reused, not duplicated. Never hard-deleted; a participant archives their own view instead.';

create index conversations_school_id_idx on public.conversations (school_id);
create index conversations_last_message_at_idx on public.conversations (school_id, last_message_at desc);

create table public.conversation_participants (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  school_id       uuid not null references public.schools (id) on delete cascade,
  profile_id      uuid not null references public.profiles (id) on delete cascade,
  last_read_at    timestamptz,
  archived        boolean not null default false,
  muted           boolean not null default false,
  added_by        uuid references public.profiles (id) on delete set null,
  added_at        timestamptz not null default now(),
  unique (conversation_id, profile_id)
);

comment on table public.conversation_participants is 'Membership of a conversation, one row per profile. last_read_at is the per-user read cursor (a message with created_at > last_read_at is unread). archived / muted are per-user views — archiving does not remove you from the thread; a new message un-archives it. Managed only via RPC, except the own-row cursor/archive/mute UPDATE.';

create index conversation_participants_profile_idx on public.conversation_participants (profile_id, archived);
create index conversation_participants_conversation_idx on public.conversation_participants (conversation_id);

create table public.messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  school_id       uuid not null references public.schools (id) on delete cascade,
  sender_profile_id uuid not null references public.profiles (id) on delete cascade,
  body            text not null check (char_length(body) > 0),
  edited_at       timestamptz,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now()
);

comment on table public.messages is 'Append-only message stream. edited_at / deleted_at are soft markers set only by the sender via edit_message() / delete_message(); a deleted message keeps its row (body replaced with a tombstone) so thread continuity and counts are stable. No client INSERT/UPDATE/DELETE policy — send_message() is the only writer.';

create index messages_conversation_idx on public.messages (conversation_id, created_at);
create index messages_school_id_idx on public.messages (school_id);
-- Search support: the service filters by plainto_tsquery over this same
-- expression, so the GIN index makes conversation search index-assisted.
create index messages_body_fts_idx on public.messages using gin (to_tsvector('simple', body));

create table public.message_attachments (
  id              uuid primary key default gen_random_uuid(),
  message_id      uuid not null references public.messages (id) on delete cascade,
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  school_id       uuid not null references public.schools (id) on delete cascade,
  label           text not null check (char_length(label) > 0),
  storage_path    text not null,
  mime_type       text,
  size_bytes      integer,
  uploaded_by     uuid references public.profiles (id) on delete set null,
  uploaded_at     timestamptz not null default now()
);

comment on table public.message_attachments is 'A file on a message. storage_path points into the private message-attachments bucket (<school_id>/<conversation_id>/<filename>). Registered by register_message_attachment() after the client uploads; the bucket RLS independently restricts read/write to conversation participants.';

create index message_attachments_message_idx on public.message_attachments (message_id);
create index message_attachments_conversation_idx on public.message_attachments (conversation_id);

-- ---------------------------------------------------------------------------
-- 5a. Helpers
-- ---------------------------------------------------------------------------

create or replace function public.is_conversation_participant(p_conversation_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_participants
    where conversation_id = p_conversation_id and profile_id = auth.uid()
  )
$$;
comment on function public.is_conversation_participant(uuid) is 'True if the caller is a participant of the conversation. SECURITY DEFINER so RLS policies on messages/attachments can call it without recursing through conversation_participants'' own policy.';
grant execute on function public.is_conversation_participant(uuid) to authenticated;

-- Is the caller allowed to open a conversation with this profile?
-- staff  -> any active profile in the same tenant
-- guardian -> only staff (never another guardian, never a learner)
-- (learner accounts do not exist yet; the same "only staff" rule is applied
--  defensively so Domain 8 inherits it.)
create or replace function public.can_message_profile(p_target_profile_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_my_tenant uuid;
  v_my_role text;
  v_target record;
begin
  if auth.uid() = p_target_profile_id then return false; end if;
  v_my_tenant := public.current_tenant_id();
  if v_my_tenant is null then return false; end if;
  v_my_role := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');

  select tenant_id, status into v_target from public.profiles where id = p_target_profile_id;
  if v_target.tenant_id is distinct from v_my_tenant or v_target.status <> 'active' then
    return false;
  end if;

  -- We hold the JWT only for the caller, not the target, so the target's
  -- "is staff" is inferred structurally: they have an employees row for
  -- this school, OR they are not anybody's guardian. A person who is both
  -- staff and a guardian is reachable (the employees row wins).
  if v_my_role in ('parent', 'guardian', 'learner') then
    return exists (select 1 from public.employees e where e.profile_id = p_target_profile_id and e.school_id = v_my_tenant)
        or not exists (select 1 from public.learner_guardians lg where lg.guardian_profile_id = p_target_profile_id);
  end if;

  -- caller is staff: may message anyone active in the tenant
  return true;
end;
$$;
comment on function public.can_message_profile(uuid) is 'Authorization gate for start_conversation()/add_conversation_participants(). staff<->anyone in tenant; guardian<->staff only. Mirrors no app Permission (messaging is open to every authenticated tenant member, like email) — the restriction is purely on the counterparty.';
grant execute on function public.can_message_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5b. Tenant-validation triggers
-- ---------------------------------------------------------------------------

create or replace function public.conversation_participants_validate_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_conv_school uuid; v_profile_tenant uuid;
begin
  select school_id into v_conv_school from public.conversations where id = new.conversation_id;
  if v_conv_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: participant school_id must match the conversation';
  end if;
  select tenant_id into v_profile_tenant from public.profiles where id = new.profile_id;
  if v_profile_tenant is distinct from new.school_id then
    raise exception 'insufficient_privilege: a participant must belong to the conversation''s school';
  end if;
  return new;
end;
$$;
create trigger conversation_participants_validate_tenant_trigger
  before insert or update on public.conversation_participants
  for each row execute function public.conversation_participants_validate_tenant();

create or replace function public.messages_validate_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_conv_school uuid;
begin
  select school_id into v_conv_school from public.conversations where id = new.conversation_id;
  if v_conv_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: message school_id must match the conversation';
  end if;
  return new;
end;
$$;
create trigger messages_validate_tenant_trigger
  before insert or update on public.messages
  for each row execute function public.messages_validate_tenant();

-- ---------------------------------------------------------------------------
-- 5c. RLS
-- ---------------------------------------------------------------------------

alter table public.conversations enable row level security;
alter table public.conversations force row level security;
alter table public.conversation_participants enable row level security;
alter table public.conversation_participants force row level security;
alter table public.messages enable row level security;
alter table public.messages force row level security;
alter table public.message_attachments enable row level security;
alter table public.message_attachments force row level security;

create policy conversations_select on public.conversations
  for select to authenticated using (public.is_conversation_participant(id) or public.is_platform_admin());
-- No client INSERT/UPDATE/DELETE — start_conversation() / send_message() own all writes.

create policy conversation_participants_select on public.conversation_participants
  for select to authenticated using (
    public.is_conversation_participant(conversation_id) or public.is_platform_admin()
  );
-- A participant may update ONLY their own row, and the protect trigger
-- pins that to the cursor/archive/mute columns.
create policy conversation_participants_update_own on public.conversation_participants
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- Guards the own-row UPDATE policy down to the three self-service columns.
-- INSERT is already impossible for `authenticated` (no INSERT policy +
-- FORCE RLS); the guard here is defence-in-depth for the SECURITY DEFINER
-- path, which sets app.allow_conversation_write first. DELETE is
-- deliberately NOT trapped — participant rows must still cascade when a
-- profile or conversation is removed.
create or replace function public.conversation_participants_protect()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('app.allow_conversation_write', true), '') = 'true' then
    return new;
  end if;
  if tg_op = 'UPDATE' and (
       new.conversation_id is distinct from old.conversation_id
    or new.profile_id      is distinct from old.profile_id
    or new.school_id       is distinct from old.school_id
    or new.added_by        is distinct from old.added_by
  ) then
    raise exception 'insufficient_privilege: only last_read_at / archived / muted may be changed directly';
  end if;
  if tg_op = 'INSERT' then
    raise exception 'insufficient_privilege: conversation participants are added only via start_conversation()/add_conversation_participants()';
  end if;
  return new;
end;
$$;
create trigger conversation_participants_protect_trigger
  before insert or update on public.conversation_participants
  for each row execute function public.conversation_participants_protect();

create policy messages_select on public.messages
  for select to authenticated using (
    public.is_conversation_participant(conversation_id) or public.is_platform_admin()
  );
-- No client writes — send_message()/edit_message()/delete_message() only.

create policy message_attachments_select on public.message_attachments
  for select to authenticated using (
    public.is_conversation_participant(conversation_id) or public.is_platform_admin()
  );

-- ===========================================================================
-- 6. Messaging RPCs
-- ===========================================================================

create or replace function public.send_message(p_conversation_id uuid, p_body text)
returns public.messages
language plpgsql security definer set search_path = public as $$
declare
  v_conv public.conversations;
  v_msg public.messages;
  v_participant record;
  v_sender_name text;
  v_link_prefix text;
begin
  select * into v_conv from public.conversations where id = p_conversation_id for update;
  if not found then raise exception 'not_found: no conversation %', p_conversation_id; end if;
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'insufficient_privilege: not a participant of this conversation';
  end if;
  if p_body is null or char_length(trim(p_body)) = 0 then raise exception 'invalid_argument: message body is required'; end if;

  insert into public.messages (conversation_id, school_id, sender_profile_id, body)
  values (p_conversation_id, v_conv.school_id, auth.uid(), trim(p_body))
  returning * into v_msg;

  update public.conversations
    set last_message_at = v_msg.created_at, message_count = message_count + 1
    where id = p_conversation_id;

  -- Sender's own read cursor advances; sender's archived view clears.
  perform set_config('app.allow_conversation_write', 'true', true);
  update public.conversation_participants
    set last_read_at = v_msg.created_at, archived = false
    where conversation_id = p_conversation_id and profile_id = auth.uid();
  -- A new message un-archives it for everyone else too.
  update public.conversation_participants
    set archived = false
    where conversation_id = p_conversation_id and profile_id <> auth.uid() and archived;
  perform set_config('app.allow_conversation_write', 'false', true);

  select (first_name || ' ' || last_name) into v_sender_name from public.profiles where id = auth.uid();

  for v_participant in
    select cp.profile_id, cp.muted,
      exists (select 1 from public.learner_guardians lg where lg.guardian_profile_id = cp.profile_id and lg.active) as is_guardian
    from public.conversation_participants cp
    where cp.conversation_id = p_conversation_id and cp.profile_id <> auth.uid()
  loop
    if v_participant.muted then continue; end if;
    v_link_prefix := case when v_participant.is_guardian then '/parent/messages/' else '/messages/' end;
    perform public.create_notification(
      v_participant.profile_id,
      'message',
      coalesce(v_sender_name, 'New message') || case when v_conv.subject is not null then ' — ' || v_conv.subject else '' end,
      left(trim(p_body), 280),
      v_conv.school_id,
      'conversations',
      p_conversation_id,
      v_link_prefix || p_conversation_id::text
    );
  end loop;

  return v_msg;
end;
$$;
revoke execute on function public.send_message(uuid, text) from public;
grant execute on function public.send_message(uuid, text) to authenticated;

create or replace function public.edit_message(p_message_id uuid, p_body text)
returns public.messages
language plpgsql security definer set search_path = public as $$
declare v_msg public.messages;
begin
  select * into v_msg from public.messages where id = p_message_id;
  if not found then raise exception 'not_found: no message %', p_message_id; end if;
  if v_msg.sender_profile_id <> auth.uid() then raise exception 'insufficient_privilege: only the sender can edit a message'; end if;
  if v_msg.deleted_at is not null then raise exception 'invalid_state: a deleted message cannot be edited'; end if;
  if p_body is null or char_length(trim(p_body)) = 0 then raise exception 'invalid_argument: message body is required'; end if;
  update public.messages set body = trim(p_body), edited_at = now() where id = p_message_id returning * into v_msg;
  return v_msg;
end;
$$;
revoke execute on function public.edit_message(uuid, text) from public;
grant execute on function public.edit_message(uuid, text) to authenticated;

create or replace function public.delete_message(p_message_id uuid)
returns public.messages
language plpgsql security definer set search_path = public as $$
declare v_msg public.messages;
begin
  select * into v_msg from public.messages where id = p_message_id;
  if not found then raise exception 'not_found: no message %', p_message_id; end if;
  if v_msg.sender_profile_id <> auth.uid() then raise exception 'insufficient_privilege: only the sender can delete a message'; end if;
  if v_msg.deleted_at is not null then return v_msg; end if;
  update public.messages set body = '(message deleted)', deleted_at = now() where id = p_message_id returning * into v_msg;
  return v_msg;
end;
$$;
revoke execute on function public.delete_message(uuid) from public;
grant execute on function public.delete_message(uuid) to authenticated;

-- start_conversation is defined after send_message because it calls it.
create or replace function public.start_conversation(
  p_participant_profile_ids uuid[],
  p_body text,
  p_subject text default null,
  p_kind public.conversation_kind default 'direct'
) returns public.conversations
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid;
  v_uniq uuid[];
  v_target uuid;
  v_conv public.conversations;
  v_existing uuid;
  v_all uuid[];
begin
  v_tenant := public.current_tenant_id();
  if v_tenant is null then raise exception 'insufficient_privilege: no tenant'; end if;
  if p_body is null or char_length(trim(p_body)) = 0 then raise exception 'invalid_argument: message body is required'; end if;

  select array_agg(distinct pid) into v_uniq
  from unnest(coalesce(p_participant_profile_ids, '{}'::uuid[])) pid
  where pid <> auth.uid();

  if v_uniq is null or array_length(v_uniq, 1) is null then
    raise exception 'invalid_argument: at least one other participant is required';
  end if;

  foreach v_target in array v_uniq loop
    if not public.can_message_profile(v_target) then
      raise exception 'insufficient_privilege: you cannot start a conversation with %', v_target;
    end if;
  end loop;

  v_all := v_uniq || auth.uid();

  -- Reuse an existing direct 2-party conversation between exactly this pair.
  if p_kind = 'direct' and array_length(v_all, 1) = 2 then
    select c.id into v_existing
    from public.conversations c
    where c.school_id = v_tenant and c.kind = 'direct'
      and (select array_agg(cp.profile_id order by cp.profile_id) from public.conversation_participants cp where cp.conversation_id = c.id)
          = (select array_agg(x order by x) from unnest(v_all) x)
    limit 1;

    if v_existing is not null then
      perform public.send_message(v_existing, p_body);
      select * into v_conv from public.conversations where id = v_existing;
      return v_conv;
    end if;
  end if;

  if p_kind = 'direct' and array_length(v_all, 1) <> 2 then
    raise exception 'invalid_argument: a direct conversation has exactly two participants (use kind => ''group'')';
  end if;

  insert into public.conversations (school_id, kind, subject, created_by)
  values (v_tenant, p_kind, nullif(trim(coalesce(p_subject, '')), ''), auth.uid())
  returning * into v_conv;

  perform set_config('app.allow_conversation_write', 'true', true);
  insert into public.conversation_participants (conversation_id, school_id, profile_id, added_by, last_read_at)
  select v_conv.id, v_tenant, pid, auth.uid(),
         case when pid = auth.uid() then now() else null end
  from unnest(v_all) pid;
  perform set_config('app.allow_conversation_write', 'false', true);

  perform public.send_message(v_conv.id, p_body);

  perform public.write_audit_log(v_tenant, auth.uid(), 'conversation_started', 'conversations', v_conv.id, null,
    jsonb_build_object('kind', p_kind, 'participants', v_all));

  select * into v_conv from public.conversations where id = v_conv.id;
  return v_conv;
end;
$$;
revoke execute on function public.start_conversation(uuid[], text, text, public.conversation_kind) from public;
grant execute on function public.start_conversation(uuid[], text, text, public.conversation_kind) to authenticated;

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'insufficient_privilege: not a participant of this conversation';
  end if;
  perform set_config('app.allow_conversation_write', 'true', true);
  update public.conversation_participants set last_read_at = now()
    where conversation_id = p_conversation_id and profile_id = auth.uid();
  perform set_config('app.allow_conversation_write', 'false', true);
end;
$$;
revoke execute on function public.mark_conversation_read(uuid) from public;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

create or replace function public.set_conversation_flags(
  p_conversation_id uuid, p_archived boolean default null, p_muted boolean default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'insufficient_privilege: not a participant of this conversation';
  end if;
  perform set_config('app.allow_conversation_write', 'true', true);
  update public.conversation_participants set
    archived = coalesce(p_archived, archived),
    muted = coalesce(p_muted, muted)
    where conversation_id = p_conversation_id and profile_id = auth.uid();
  perform set_config('app.allow_conversation_write', 'false', true);
end;
$$;
revoke execute on function public.set_conversation_flags(uuid, boolean, boolean) from public;
grant execute on function public.set_conversation_flags(uuid, boolean, boolean) to authenticated;

create or replace function public.add_conversation_participants(
  p_conversation_id uuid, p_profile_ids uuid[]
) returns public.conversations
language plpgsql security definer set search_path = public as $$
declare
  v_conv public.conversations;
  v_target uuid;
  v_added uuid[] := '{}';
begin
  select * into v_conv from public.conversations where id = p_conversation_id for update;
  if not found then raise exception 'not_found: no conversation %', p_conversation_id; end if;
  if not public.is_conversation_participant(p_conversation_id) then
    raise exception 'insufficient_privilege: not a participant of this conversation';
  end if;
  if v_conv.kind <> 'group' then
    raise exception 'invalid_state: participants can only be added to a group conversation';
  end if;
  -- Only staff may add people (a guardian cannot pull other people into a thread).
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('parent', 'guardian', 'learner') then
    raise exception 'insufficient_privilege: only staff can add conversation participants';
  end if;

  foreach v_target in array coalesce(p_profile_ids, '{}'::uuid[]) loop
    if v_target = auth.uid() then continue; end if;
    if exists (select 1 from public.conversation_participants where conversation_id = p_conversation_id and profile_id = v_target) then
      continue;
    end if;
    if not public.can_message_profile(v_target) then
      raise exception 'insufficient_privilege: you cannot add %', v_target;
    end if;
    perform set_config('app.allow_conversation_write', 'true', true);
    insert into public.conversation_participants (conversation_id, school_id, profile_id, added_by)
    values (p_conversation_id, v_conv.school_id, v_target, auth.uid());
    perform set_config('app.allow_conversation_write', 'false', true);
    v_added := v_added || v_target;
  end loop;

  if array_length(v_added, 1) is not null then
    perform public.write_audit_log(v_conv.school_id, auth.uid(), 'conversation_participants_added', 'conversations', p_conversation_id, null,
      jsonb_build_object('added', v_added));
  end if;
  return v_conv;
end;
$$;
revoke execute on function public.add_conversation_participants(uuid, uuid[]) from public;
grant execute on function public.add_conversation_participants(uuid, uuid[]) to authenticated;

create or replace function public.register_message_attachment(
  p_message_id uuid, p_label text, p_storage_path text, p_mime_type text default null, p_size_bytes integer default null
) returns public.message_attachments
language plpgsql security definer set search_path = public as $$
declare v_msg public.messages; v_att public.message_attachments;
begin
  select * into v_msg from public.messages where id = p_message_id;
  if not found then raise exception 'not_found: no message %', p_message_id; end if;
  if v_msg.sender_profile_id <> auth.uid() then raise exception 'insufficient_privilege: only the sender can attach to a message'; end if;
  if p_label is null or char_length(trim(p_label)) = 0 then raise exception 'invalid_argument: label is required'; end if;
  insert into public.message_attachments (message_id, conversation_id, school_id, label, storage_path, mime_type, size_bytes, uploaded_by)
  values (p_message_id, v_msg.conversation_id, v_msg.school_id, trim(p_label), p_storage_path, p_mime_type, p_size_bytes, auth.uid())
  returning * into v_att;
  return v_att;
end;
$$;
revoke execute on function public.register_message_attachment(uuid, text, text, text, integer) from public;
grant execute on function public.register_message_attachment(uuid, text, text, text, integer) to authenticated;

-- ===========================================================================
-- 7. New producer — guardian-visible behaviour incident notifies guardians
-- ===========================================================================

create or replace function public.behaviour_incidents_notify_guardians()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_learner_name text;
  v_guardian record;
  v_type_label text;
begin
  -- Fire only when the incident is (now) guardian-visible and active, and
  -- only on the transition into that state (INSERT already true, or
  -- UPDATE flipping false -> true) so an edit to an already-visible
  -- incident does not re-notify.
  if not (new.guardian_visible and new.active) then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.guardian_visible and old.active then
    return new;
  end if;

  -- Idempotency backstop: never a second notification for the same incident
  -- to the same guardian.
  select (first_name || ' ' || last_name) into v_learner_name from public.learners where id = new.learner_id;
  v_type_label := case when new.incident_type = 'positive' then 'A positive behaviour note has been recorded'
                       else 'A behaviour incident has been recorded' end;

  for v_guardian in
    select guardian_profile_id from public.learner_guardians where learner_id = new.learner_id and active
  loop
    if exists (
      select 1 from public.notifications
      where recipient_profile_id = v_guardian.guardian_profile_id
        and type = 'behaviour_incident' and related_entity_id = new.id
    ) then
      continue;
    end if;
    perform public.create_notification(
      v_guardian.guardian_profile_id,
      'behaviour_incident',
      v_type_label,
      v_type_label || ' for ' || coalesce(v_learner_name, 'your child') || '.',
      new.school_id,
      'behaviour_incidents',
      new.id,
      '/parent/children/' || new.learner_id::text
    );
  end loop;

  return new;
end;
$$;

comment on function public.behaviour_incidents_notify_guardians() is
  'AFTER INSERT OR UPDATE trigger on behaviour_incidents — when an incident is (or becomes) guardian_visible + active, notifies the learner''s active guardians once each (via create_notification()). Respects the same opt-in visibility model as get_guardian_visible_behaviour_incidents(): a non-guardian_visible incident never notifies. returns trigger, so it cannot be invoked directly via RPC.';

create trigger behaviour_incidents_notify_guardians_trigger
  after insert or update on public.behaviour_incidents
  for each row execute function public.behaviour_incidents_notify_guardians();

-- ===========================================================================
-- 8. Private storage bucket for message attachments
-- ===========================================================================

insert into storage.buckets (id, name, public)
values ('message-attachments', 'message-attachments', false)
on conflict (id) do nothing;

-- Path convention: <school_id>/<conversation_id>/<filename>. Any participant
-- of the conversation may read; the uploader (also a participant) may write.
create policy message_attachments_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'message-attachments'
    and public.is_conversation_participant((storage.foldername(name))[2]::uuid)
  );
create policy message_attachments_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'message-attachments'
    and public.is_conversation_participant((storage.foldername(name))[2]::uuid)
  );
