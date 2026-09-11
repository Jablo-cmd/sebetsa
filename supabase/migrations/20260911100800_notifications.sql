-- Sebetsa Phase C — Notification Engine Foundation
-- Pattern reused from Funda360's notifications.sql: durable in-app
-- notifications + a SECURITY DEFINER write path. Real email/SMS delivery is
-- out of scope here — email_status is the documented hand-off point for the
-- notifications-dispatch Edge Function (carried forward unmodified).

create type public.notification_email_status as enum ('not_sent', 'sent', 'failed');

create table public.notifications (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid references public.organizations (id) on delete cascade,
  recipient_profile_id  uuid not null references public.profiles (id) on delete cascade,
  type                  text not null check (char_length(type) > 0),
  title                 text not null check (char_length(title) > 0),
  body                  text not null check (char_length(body) > 0),
  related_entity_table  text,
  related_entity_id     uuid,
  link_path             text,
  email_status          public.notification_email_status not null default 'not_sent',
  read_at               timestamptz,
  created_at            timestamptz not null default now()
);

comment on column public.notifications.type is 'A short, stable machine-readable label (e.g. "task_assigned", "shift_changed", "incident_assigned", "certification_expiring") — not free text.';

create index notifications_recipient_unread_idx on public.notifications (recipient_profile_id, read_at);
create index notifications_tenant_id_idx on public.notifications (tenant_id);
create index notifications_created_at_idx on public.notifications (created_at);

create or replace function public.create_notification(
  p_recipient_profile_id  uuid,
  p_type                  text,
  p_title                 text,
  p_body                  text,
  p_tenant_id             uuid default null,
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
    tenant_id, recipient_profile_id, type, title, body, related_entity_table, related_entity_id, link_path
  ) values (
    p_tenant_id, p_recipient_profile_id, p_type, p_title, p_body, p_related_entity_table, p_related_entity_id, p_link_path
  )
  returning * into v_result;
  return v_result;
end;
$$;

comment on function public.create_notification(uuid, text, text, text, uuid, text, uuid, text) is
  'SECURITY DEFINER insertion point, called explicitly from inside a privileged RPC''s own body. Not granted to authenticated — a client picking its own recipient/content would be a spoofing vector.';

revoke execute on function public.create_notification(uuid, text, text, text, uuid, text, uuid, text) from public;

alter table public.notifications enable row level security;
alter table public.notifications force row level security;

create policy notifications_select_own on public.notifications
  for select to authenticated using (recipient_profile_id = auth.uid());

create policy notifications_update_own on public.notifications
  for update to authenticated using (recipient_profile_id = auth.uid()) with check (recipient_profile_id = auth.uid());
