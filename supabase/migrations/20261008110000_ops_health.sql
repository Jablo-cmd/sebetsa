-- Operational health snapshot for the health endpoint and alerting. service_role only; returns counts and
-- ages, never personal data, destinations or message bodies.
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
                          'expire_qualifications', 'audit_retention']) as e(name)
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
                          where status in ('claimed', 'processing') and claim_expires_at < now())),
    'security', jsonb_build_object(
      'failures_1h', (select count(*) from public.audit_log
                       where category = 'security' and outcome <> 'success' and created_at > now() - interval '1 hour'),
      'events_24h', (select count(*) from public.audit_log
                      where category = 'security' and created_at > now() - interval '24 hours'))
  )
$$;

revoke execute on function public.ops_health() from public, anon, authenticated;
grant execute on function public.ops_health() to service_role;

comment on function public.ops_health() is
  'Counts and ages only (no PII). Consumed by the ops-health Edge Function; thresholds live in supabase/functions/ops-health/logic.ts.';
