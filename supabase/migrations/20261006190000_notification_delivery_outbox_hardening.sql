-- Sebetsa enterprise notification outbox hardening.
-- Atomic claiming prevents duplicate processing when multiple dispatch workers run concurrently.

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  channel text not null check (channel in ('email', 'sms', 'whatsapp')),
  destination text,
  status text not null default 'pending' check (status in ('pending', 'claimed', 'processing', 'sent', 'failed', 'dead_letter')),
  attempts integer not null default 0 check (attempts >= 0),
  scheduled_for timestamptz not null default now(),
  claimed_at timestamptz,
  claim_expires_at timestamptz,
  worker_id text,
  sent_at timestamptz,
  provider_message_id text,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index notification_deliveries_dispatch_idx
  on public.notification_deliveries (status, scheduled_for, claim_expires_at);

create index notification_deliveries_notification_idx
  on public.notification_deliveries (notification_id);

create index notification_deliveries_recipient_idx
  on public.notification_deliveries (recipient_profile_id, created_at desc);

create unique index notification_deliveries_provider_message_idx
  on public.notification_deliveries (provider_message_id)
  where provider_message_id is not null;

create trigger notification_deliveries_set_updated_at
  before update on public.notification_deliveries
  for each row execute function public.set_updated_at();

alter table public.notification_deliveries enable row level security;
alter table public.notification_deliveries force row level security;

create policy notification_deliveries_select_own on public.notification_deliveries
  for select to authenticated
  using (recipient_profile_id = auth.uid());

-- Atomic worker claim. Expired claims become eligible again.
create or replace function public.claim_notification_deliveries(
  p_limit integer default 50,
  p_worker_id text default null,
  p_lease_seconds integer default 300
) returns setof public.notification_deliveries
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_limit < 1 or p_limit > 200 then
    raise exception 'invalid_limit';
  end if;
  if p_lease_seconds < 30 or p_lease_seconds > 3600 then
    raise exception 'invalid_lease_seconds';
  end if;

  return query
  with candidates as (
    select d.id
    from public.notification_deliveries d
    where
      (
        (d.status = 'pending' and d.scheduled_for <= now())
        or
        (d.status in ('claimed', 'processing')
          and d.claim_expires_at is not null
          and d.claim_expires_at < now())
      )
      and d.attempts < 5
    order by d.scheduled_for, d.created_at
    for update skip locked
    limit p_limit
  )
  update public.notification_deliveries d
  set
    status = 'claimed',
    claimed_at = now(),
    claim_expires_at = now() + make_interval(secs => p_lease_seconds),
    worker_id = coalesce(nullif(trim(p_worker_id), ''), 'unknown'),
    updated_at = now()
  from candidates c
  where d.id = c.id
  returning d.*;
end;
$$;

revoke all on function public.claim_notification_deliveries(integer, text, integer) from public;
revoke all on function public.claim_notification_deliveries(integer, text, integer) from anon;
revoke all on function public.claim_notification_deliveries(integer, text, integer) from authenticated;
grant execute on function public.claim_notification_deliveries(integer, text, integer) to service_role;

comment on function public.claim_notification_deliveries(integer, text, integer)
  is 'Atomically claims notification outbox rows using row locking and lease expiry. Service-role only.';

revoke all on table public.notification_deliveries from anon;
