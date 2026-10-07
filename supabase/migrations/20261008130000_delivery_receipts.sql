-- Provider delivery receipts.
--
-- The outbox says a message was handed to a provider ('sent'). Receipts say what happened afterwards
-- (delivered, bounced, failed...). They are recorded in separate columns and an event log, never in the
-- outbox's own state columns (status, claim, lease, worker_id, attempts), so claim / lease / SKIP LOCKED /
-- fencing semantics are untouched.
--
--   * Idempotent: unique (provider, provider_event_id); a replayed webhook changes nothing.
--   * Monotonic: a later/worse status never regresses to an earlier one (rank), so out-of-order delivery of
--     events is safe.
--   * Early receipts (the webhook beating the dispatcher's own bookkeeping) are stored unmatched and applied
--     by reconcile_delivery_receipts(), run by the scheduled job 'reconcile_receipts'.
--   * Service role only. No browser session can write or read the event log.

alter table public.notification_deliveries
  add column provider text check (provider is null or provider in ('resend', 'twilio')),
  add column provider_status text check (provider_status is null or provider_status in
    ('accepted', 'sent', 'delayed', 'delivered', 'read', 'failed', 'bounced', 'complained')),
  add column provider_status_at timestamptz,
  add column delivered_at timestamptz,
  add column provider_error text;

create table public.notification_delivery_events (
  id                  uuid primary key default gen_random_uuid(),
  provider            text not null check (provider in ('resend', 'twilio')),
  provider_event_id   text not null check (char_length(provider_event_id) between 1 and 200),
  provider_message_id text not null check (char_length(provider_message_id) between 1 and 200),
  delivery_id         uuid references public.notification_deliveries (id) on delete set null,
  event_type          text not null check (event_type in
    ('accepted', 'sent', 'delayed', 'delivered', 'read', 'failed', 'bounced', 'complained')),
  occurred_at         timestamptz not null,
  received_at         timestamptz not null default now(),
  applied             boolean not null default false,
  detail              text,
  unique (provider, provider_event_id)
);

create index notification_delivery_events_delivery_idx on public.notification_delivery_events (delivery_id);
create index notification_delivery_events_unmatched_idx on public.notification_delivery_events (received_at)
  where delivery_id is null and not applied;
create index notification_delivery_events_message_idx on public.notification_delivery_events (provider_message_id);

alter table public.notification_delivery_events enable row level security;
alter table public.notification_delivery_events force row level security;
revoke all on public.notification_delivery_events from anon, authenticated;

create or replace function public.receipt_rank(p_status text)
returns integer
language sql
immutable
set search_path = public
as $$
  select case p_status
    when 'accepted' then 1 when 'sent' then 2 when 'delayed' then 2
    when 'delivered' then 3 when 'read' then 4
    when 'failed' then 5 when 'bounced' then 5 when 'complained' then 6
    else 0 end
$$;

-- Applies one stored event to its delivery. Returns true when the delivery changed.
create or replace function public.apply_delivery_receipt(p_event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.notification_delivery_events;
  v_delivery public.notification_deliveries;
  v_changed boolean := false;
begin
  select * into v_event from public.notification_delivery_events where id = p_event_id for update;
  if not found then return false; end if;

  select d.* into v_delivery
    from public.notification_deliveries d
   where d.provider_message_id = v_event.provider_message_id
     and ((v_event.provider = 'resend' and d.channel = 'email')
       or (v_event.provider = 'twilio' and d.channel in ('sms', 'whatsapp')))
   for update;
  if not found then return false; end if;

  if public.receipt_rank(v_event.event_type) > public.receipt_rank(v_delivery.provider_status) then
    update public.notification_deliveries
       set provider = v_event.provider,
           provider_status = v_event.event_type,
           provider_status_at = v_event.occurred_at,
           delivered_at = case when v_event.event_type in ('delivered', 'read') then coalesce(delivered_at, v_event.occurred_at) else delivered_at end,
           provider_error = case when v_event.event_type in ('failed', 'bounced', 'complained') then left(coalesce(v_event.detail, v_event.event_type), 200) else provider_error end
     where id = v_delivery.id;
    v_changed := true;
  end if;

  update public.notification_delivery_events set delivery_id = v_delivery.id, applied = true where id = v_event.id;
  return v_changed;
end;
$$;

create or replace function public.record_delivery_receipt(
  p_provider text,
  p_event_id text,
  p_message_id text,
  p_event_type text,
  p_occurred_at timestamptz,
  p_detail text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_matched boolean;
begin
  insert into public.notification_delivery_events (provider, provider_event_id, provider_message_id, event_type, occurred_at, detail)
  values (p_provider, p_event_id, p_message_id, p_event_type, coalesce(p_occurred_at, now()), left(p_detail, 200))
  on conflict (provider, provider_event_id) do nothing
  returning id into v_id;

  if v_id is null then
    return 'duplicate';
  end if;

  perform public.apply_delivery_receipt(v_id);
  select applied into v_matched from public.notification_delivery_events where id = v_id;
  return case when v_matched then 'applied' else 'unmatched' end;
end;
$$;

-- Applies receipts that arrived before the delivery knew its provider message id. Events never matched
-- within 7 days are left in place (visible through ops_health) and no longer retried.
create or replace function public.reconcile_delivery_receipts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event record;
  v_count integer := 0;
begin
  for v_event in
    select id from public.notification_delivery_events
     where not applied and received_at > now() - interval '7 days'
     order by occurred_at
  loop
    if public.apply_delivery_receipt(v_event.id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.receipt_rank(text) from public, anon, authenticated;
revoke execute on function public.apply_delivery_receipt(uuid) from public, anon, authenticated;
revoke execute on function public.record_delivery_receipt(text, text, text, text, timestamptz, text) from public, anon, authenticated;
revoke execute on function public.reconcile_delivery_receipts() from public, anon, authenticated;
grant execute on function public.record_delivery_receipt(text, text, text, text, timestamptz, text) to service_role;
grant execute on function public.reconcile_delivery_receipts() to service_role;

-- ---------------------------------------------------------------------------
-- Scheduler: add the receipt-reconciliation job (global, like audit_retention).
-- ---------------------------------------------------------------------------
create or replace function public.run_scheduled_job(p_job text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant record;
  v_run uuid;
  v_count integer;
  v_failed integer := 0;
  v_done integer := 0;
  v_deleted bigint;
begin
  if p_job not in ('recurring_tasks', 'escalate_overdue', 'expire_documents', 'expire_compliance', 'expire_qualifications',
                   'audit_retention', 'reconcile_receipts') then
    raise exception 'invalid_parameter: unknown job %', p_job;
  end if;

  if not pg_try_advisory_xact_lock(hashtextextended('sebetsa:job:' || p_job, 0)) then
    insert into public.job_runs (job_name, status, finished_at) values (p_job, 'skipped_locked', now());
    return jsonb_build_object('job', p_job, 'status', 'skipped_locked');
  end if;

  if p_job in ('audit_retention', 'reconcile_receipts') then
    insert into public.job_runs (job_name, status) values (p_job, 'running') returning id into v_run;
    begin
      if p_job = 'audit_retention' then
        v_deleted := public.purge_audit_log();
        perform public.write_security_audit_event(null, null, 'audit_retention_run', 'audit_log', '00000000-0000-0000-0000-000000000000', 'success',
                                                  jsonb_build_object('deleted', v_deleted, 'window', '7 years'));
      else
        v_deleted := public.reconcile_delivery_receipts();
      end if;
      update public.job_runs set status = 'succeeded', rows_affected = v_deleted, finished_at = now() where id = v_run;
      return jsonb_build_object('job', p_job, 'status', 'succeeded', 'rows', v_deleted);
    exception when others then
      update public.job_runs set status = 'failed', error = left(sqlerrm, 500), finished_at = now() where id = v_run;
      return jsonb_build_object('job', p_job, 'status', 'failed');
    end;
  end if;

  for v_tenant in select id from public.organizations where status = 'active' order by id loop
    insert into public.job_runs (job_name, tenant_id, status) values (p_job, v_tenant.id, 'running') returning id into v_run;
    begin
      v_count := case p_job
        when 'recurring_tasks' then (select count(*) from public.job_generate_recurring_tasks(v_tenant.id))
        when 'escalate_overdue' then (select count(*) from public.job_escalate_overdue_tasks(v_tenant.id))
        when 'expire_documents' then (select count(*) from public.job_sync_expired_documents(v_tenant.id))
        when 'expire_compliance' then (select count(*) from public.job_sync_expired_compliance_records(v_tenant.id))
        when 'expire_qualifications' then (select count(*) from public.job_sync_expired_qualifications(v_tenant.id))
      end;
      update public.job_runs set status = 'succeeded', rows_affected = v_count, finished_at = now() where id = v_run;
      v_done := v_done + 1;
    exception when others then
      update public.job_runs set status = 'failed', error = left(sqlerrm, 500), finished_at = now() where id = v_run;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object('job', p_job, 'status', case when v_failed = 0 then 'succeeded' else 'partial_failure' end,
                            'tenants_succeeded', v_done, 'tenants_failed', v_failed);
end;
$$;

revoke execute on function public.run_scheduled_job(text) from public, anon, authenticated;
grant execute on function public.run_scheduled_job(text) to service_role;

create or replace function public.schedule_platform_jobs()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not installed: enable it, then run select public.schedule_platform_jobs();';
  end if;
  for v_job in
    select * from (values
      ('sebetsa-recurring-tasks',   '5 0 * * *',  'recurring_tasks'),
      ('sebetsa-escalate-overdue',  '*/15 * * * *', 'escalate_overdue'),
      ('sebetsa-expire-documents',  '15 0 * * *', 'expire_documents'),
      ('sebetsa-expire-compliance', '20 0 * * *', 'expire_compliance'),
      ('sebetsa-expire-qualifications', '25 0 * * *', 'expire_qualifications'),
      ('sebetsa-audit-retention',   '30 2 * * 0', 'audit_retention'),
      ('sebetsa-reconcile-receipts', '*/10 * * * *', 'reconcile_receipts')
    ) as t(name, schedule, job)
  loop
    execute format('select cron.unschedule(jobid) from cron.job where jobname = %L', v_job.name);
    execute format('select cron.schedule(%L, %L, %L)', v_job.name, v_job.schedule,
                   format('select public.run_scheduled_job(%L)', v_job.job));
  end loop;
  return 'scheduled';
end;
$$;

revoke execute on function public.schedule_platform_jobs() from public, anon, authenticated;
grant execute on function public.schedule_platform_jobs() to service_role;

-- ---------------------------------------------------------------------------
-- ops_health: add receipt counters and the new job.
-- ---------------------------------------------------------------------------
create or replace function public.ops_health()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'checked_at', now(),
    'database', 'ok',
    'jobs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'job', j.job_name,
        'last_success_at', j.last_success_at,
        'last_status', j.last_status,
        'failures_since_success', j.failures_since_success))
        from public.job_health() j), '[]'::jsonb),
    'jobs_never_ran', coalesce((
      select jsonb_agg(e.name order by e.name)
        from unnest(array['recurring_tasks', 'escalate_overdue', 'expire_documents', 'expire_compliance',
                          'expire_qualifications', 'audit_retention', 'reconcile_receipts']) as e(name)
       where not exists (select 1 from public.job_runs r where r.job_name = e.name and r.status = 'succeeded')), '[]'::jsonb),
    'notifications', jsonb_build_object(
      'pending_overdue', (select count(*) from public.notification_deliveries
                           where status = 'pending' and scheduled_for < now() - interval '15 minutes'),
      'oldest_pending_age_seconds', (select coalesce(extract(epoch from now() - min(scheduled_for))::bigint, 0)
                                       from public.notification_deliveries
                                      where status = 'pending' and scheduled_for < now()),
      'dead_letter', (select count(*) from public.notification_deliveries where status = 'dead_letter'),
      'dead_letter_24h', (select count(*) from public.notification_deliveries
                           where status = 'dead_letter' and updated_at > now() - interval '24 hours'),
      'expired_leases', (select count(*) from public.notification_deliveries
                          where status in ('claimed', 'processing') and claim_expires_at < now()),
      'receipt_failures_24h', (select count(*) from public.notification_deliveries
                                where provider_status in ('failed', 'bounced', 'complained')
                                  and provider_status_at > now() - interval '24 hours'),
      'sent_without_receipt', (select count(*) from public.notification_deliveries
                                where status = 'sent' and provider_status is null and sent_at < now() - interval '1 hour'
                                  and sent_at > now() - interval '24 hours'),
      'unmatched_receipts', (select count(*) from public.notification_delivery_events
                              where not applied and received_at > now() - interval '7 days')),
    'security', jsonb_build_object(
      'failures_1h', (select count(*) from public.audit_log
                       where category = 'security' and outcome <> 'success' and created_at > now() - interval '1 hour'),
      'events_24h', (select count(*) from public.audit_log
                      where category = 'security' and created_at > now() - interval '24 hours'))
  )
$$;

revoke execute on function public.ops_health() from public, anon, authenticated;
grant execute on function public.ops_health() to service_role;
