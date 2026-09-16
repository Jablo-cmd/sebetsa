-- Sebetsa Domain 14 (part 3) — notification delivery abstraction.
--
-- Sebetsa's existing `notifications` table (20260911100800) is the in-app
-- channel — already real, already working. This adds the delivery-tracking
-- layer a real push/SMS channel needs (attempt/retry/dedup state) without
-- hardwiring the app to one provider. The actual "send a push to a device"
-- call is a TypeScript-layer provider interface (see
-- src/features/notifications/services/notificationProviders/), not
-- something this migration can implement — no push/SMS provider
-- credentials exist anywhere in this repository, so there is no real
-- external service this migration could honestly claim to call. What is
-- built here is the complete, real delivery-tracking data model that
-- provider will write into once one is configured.

create type public.notification_channel as enum ('in_app', 'push', 'sms');
create type public.notification_delivery_status as enum ('pending', 'sent', 'delivered', 'failed');

create table public.notification_deliveries (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  notification_id   uuid not null references public.notifications (id) on delete cascade,
  channel           public.notification_channel not null,
  provider          text,
  delivery_status   public.notification_delivery_status not null default 'pending',
  attempt_count     integer not null default 0,
  last_attempted_at timestamptz,
  error_message     text,
  created_at        timestamptz not null default now()
);

comment on table public.notification_deliveries is
  'One row per (notification, channel) delivery attempt tracked. in_app deliveries are recorded as sent immediately (the notifications row itself is the delivery). push/sms rows start pending and are updated by the corresponding provider once one is configured — see src/features/notifications/services/notificationProviders/.';

create index notification_deliveries_notification_idx on public.notification_deliveries (notification_id);
create index notification_deliveries_tenant_status_idx on public.notification_deliveries (tenant_id, delivery_status);
create unique index notification_deliveries_dedup_idx on public.notification_deliveries (notification_id, channel);

create or replace function public.validate_notification_delivery_tenant_refs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.notifications where id = new.notification_id and (tenant_id = new.tenant_id or tenant_id is null)) then
    raise exception 'cross_tenant_reference: notification % does not belong to tenant %', new.notification_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger notification_deliveries_validate_tenant_refs
  before insert or update on public.notification_deliveries
  for each row
  execute function public.validate_notification_delivery_tenant_refs();

alter table public.notification_deliveries enable row level security;
alter table public.notification_deliveries force row level security;

-- Same visibility as the notification it belongs to: the recipient, or
-- the operations-management tier troubleshooting delivery failures.
create policy notification_deliveries_select on public.notification_deliveries for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.notifications n where n.id = notification_deliveries.notification_id and n.recipient_profile_id = auth.uid())
  );

-- No direct client write policy — record_notification_delivery()/
-- update_notification_delivery_status() RPCs only.

create or replace function public.record_notification_delivery(
  p_notification_id uuid,
  p_channel public.notification_channel,
  p_provider text default null
)
returns public.notification_deliveries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.notification_deliveries;
begin
  select tenant_id into v_tenant_id from public.notifications where id = p_notification_id;
  if not found then
    raise exception 'not_found: no notification %', p_notification_id;
  end if;

  insert into public.notification_deliveries (tenant_id, notification_id, channel, provider, delivery_status, attempt_count, last_attempted_at)
  values (v_tenant_id, p_notification_id, p_channel, p_provider, case when p_channel = 'in_app' then 'delivered' else 'pending' end::public.notification_delivery_status, 1, now())
  on conflict (notification_id, channel) do update set attempt_count = notification_deliveries.attempt_count + 1, last_attempted_at = now()
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.record_notification_delivery(uuid, public.notification_channel, text) from public, anon;
grant execute on function public.record_notification_delivery(uuid, public.notification_channel, text) to authenticated;

create or replace function public.update_notification_delivery_status(
  p_delivery_id uuid,
  p_status public.notification_delivery_status,
  p_error_message text default null
)
returns public.notification_deliveries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_delivery public.notification_deliveries;
  v_result public.notification_deliveries;
begin
  select * into v_delivery from public.notification_deliveries where id = p_delivery_id;
  if not found then
    raise exception 'not_found: no notification delivery %', p_delivery_id;
  end if;
  if not public.can_manage_operations(v_delivery.tenant_id) then
    raise exception 'insufficient_privilege: cannot update delivery status for this tenant';
  end if;

  update public.notification_deliveries set delivery_status = p_status, error_message = p_error_message
    where id = p_delivery_id returning * into v_result;
  return v_result;
end;
$$;

revoke execute on function public.update_notification_delivery_status(uuid, public.notification_delivery_status, text) from public, anon;
grant execute on function public.update_notification_delivery_status(uuid, public.notification_delivery_status, text) to authenticated;
