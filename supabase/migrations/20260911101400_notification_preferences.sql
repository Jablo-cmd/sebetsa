-- Sebetsa Phase D — per-user notification channel preferences.

create table public.notification_preferences (
  profile_id        uuid primary key references public.profiles (id) on delete cascade,
  email_enabled     boolean not null default false,
  sms_enabled       boolean not null default false,
  whatsapp_enabled  boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end   time,
  updated_at        timestamptz not null default now()
);

create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row
  execute function public.set_updated_at();

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;

create policy notification_preferences_select_own on public.notification_preferences
  for select to authenticated using (profile_id = auth.uid());

create policy notification_preferences_upsert_own on public.notification_preferences
  for insert to authenticated with check (profile_id = auth.uid());

create policy notification_preferences_update_own on public.notification_preferences
  for update to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
