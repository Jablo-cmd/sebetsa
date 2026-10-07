-- Scheduled jobs: recurring tasks, overdue escalation, expiry sweeps, audit retention.
--
-- Design
--   * The manager RPCs (generate_recurring_tasks, escalate_overdue_tasks, sync_expired_*) stay as they
--     were for the UI: they check the caller and then delegate to an internal `job_*` function.
--   * The internal functions have no caller check and are executable by service_role only, so a normal
--     user can never reach them directly.
--   * run_scheduled_job(name) is the only entry point for schedulers (pg_cron, or an Edge Function with the
--     service role). It takes a job-wide advisory lock (two overlapping runs cannot both work), runs each
--     tenant in its own sub-transaction (one tenant failing does not stop the others), and records every
--     run in job_runs.
--   * Every job is idempotent, so a retry after a crash is safe:
--       generate_recurring_tasks  one task per template per period (last_generated_on, row-locked)
--       escalate_overdue_tasks    only open/in_progress tasks are escalated, once; they are then 'escalated'
--       sync_expired_*            only rows not yet expired are flipped, once
--       audit_retention           deletes only rows past the window; logs a security audit event
--   * Retention is auditable: every purge writes a `audit_retention_run` security event with the count.

create table public.job_runs (
  id            uuid primary key default gen_random_uuid(),
  job_name      text not null,
  tenant_id     uuid references public.organizations (id) on delete cascade,
  status        text not null check (status in ('running', 'succeeded', 'failed', 'skipped_locked')),
  rows_affected integer not null default 0,
  error         text,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz
);

create index job_runs_job_started_idx on public.job_runs (job_name, started_at desc);
create index job_runs_tenant_idx on public.job_runs (tenant_id, started_at desc);

alter table public.job_runs enable row level security;
alter table public.job_runs force row level security;

-- Tenant administrators see their own tenant's runs; platform administrators see all (including global runs).
create policy job_runs_select on public.job_runs for select to authenticated
  using (
    (tenant_id is not null and tenant_id = public.current_tenant_id()
       and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'organization_administrator')
    or public.is_platform_admin()
  );
revoke all on public.job_runs from anon, authenticated;
grant select on public.job_runs to authenticated;

comment on table public.job_runs is
  'One row per scheduled job execution per tenant (or global). Written only by run_scheduled_job().';

-- ---------------------------------------------------------------------------
-- Internal job bodies (no caller check; service_role only).
-- ---------------------------------------------------------------------------

create or replace function public.job_generate_recurring_tasks(p_tenant_id uuid)
returns setof public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template record;
  v_period_start date;
  v_new_task public.tasks;
begin
  for v_template in
    select * from public.task_templates
    where tenant_id = p_tenant_id and status = 'active' and recurrence_frequency is not null
    order by id
    for update
  loop
    v_period_start := case v_template.recurrence_frequency
      when 'daily' then current_date
      when 'weekly' then date_trunc('week', current_date)::date
      when 'monthly' then date_trunc('month', current_date)::date
    end;

    if v_template.last_generated_on is not null and v_template.last_generated_on >= v_period_start then
      continue;
    end if;

    insert into public.tasks (
      tenant_id, site_id, assignee_id, team_id, supervisor_id, title, description, priority, requires_evidence, created_by
    ) values (
      v_template.tenant_id, v_template.site_id, v_template.default_assignee_id, v_template.default_team_id, null,
      v_template.title, v_template.description, v_template.priority, v_template.requires_evidence, auth.uid()
    )
    returning * into v_new_task;

    if v_template.instructions is not null then
      insert into public.task_comments (tenant_id, task_id, author_id, body)
      values (v_template.tenant_id, v_new_task.id, auth.uid(), v_template.instructions);
    end if;

    update public.task_templates set last_generated_on = v_period_start where id = v_template.id;

    perform public.write_audit_log(v_template.tenant_id, auth.uid(), 'task_generated_from_template', 'tasks', v_new_task.id, null, jsonb_build_object('task_template_id', v_template.id));

    return next v_new_task;
  end loop;
end;
$$;

create or replace function public.job_escalate_overdue_tasks(p_tenant_id uuid)
returns setof public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task record;
  v_supervisor_profile_id uuid;
begin
  for v_task in
    update public.tasks
    set status = 'escalated'
    where tenant_id = p_tenant_id
      and status in ('open', 'in_progress')
      and due_at is not null
      and due_at < now()
    returning *
  loop
    if v_task.supervisor_id is not null then
      select profile_id into v_supervisor_profile_id from public.employees where id = v_task.supervisor_id;
      if v_supervisor_profile_id is not null then
        perform public.create_notification(
          v_supervisor_profile_id, 'task_escalated', 'Task overdue: ' || v_task.title,
          'A task assigned to your team is now overdue and has been escalated.',
          p_tenant_id, 'tasks', v_task.id, null
        );
      end if;
    end if;

    perform public.write_audit_log(p_tenant_id, auth.uid(), 'task_escalated', 'tasks', v_task.id, null, jsonb_build_object('due_at', v_task.due_at));
    return next v_task;
  end loop;
end;
$$;

create or replace function public.job_sync_expired_documents(p_tenant_id uuid)
returns setof public.employee_documents
language sql
security definer
set search_path = public
as $$
  update public.employee_documents
  set status = 'expired'
  where tenant_id = p_tenant_id
    and status = 'verified'
    and expiry_date is not null
    and expiry_date < current_date
  returning *
$$;

create or replace function public.job_sync_expired_compliance_records(p_tenant_id uuid)
returns setof public.compliance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record record;
begin
  for v_record in
    update public.compliance_records
    set status = 'expired'
    where tenant_id = p_tenant_id
      and status not in ('expired', 'waived')
      and expiry_date is not null
      and expiry_date < current_date
    returning *
  loop
    if v_record.responsible_profile_id is not null then
      perform public.create_notification(
        v_record.responsible_profile_id, 'compliance_expired', 'Compliance record expired',
        'A compliance record you are responsible for has expired and needs renewal.',
        p_tenant_id, 'compliance_records', v_record.id, null
      );
    end if;
    return next v_record;
  end loop;
end;
$$;

create or replace function public.job_sync_expired_qualifications(p_tenant_id uuid)
returns setof public.employee_qualifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  for v_row in
    update public.employee_qualifications
    set status = 'expired'
    where tenant_id = p_tenant_id
      and status not in ('expired', 'revoked')
      and expiry_date is not null
      and expiry_date < current_date
    returning *
  loop
    perform public.write_audit_log(p_tenant_id, auth.uid(), 'employee_qualification_expired', 'employee_qualifications', v_row.id, null, jsonb_build_object('status', 'expired'));
    return next v_row;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- The manager RPCs become thin permission wrappers (behaviour unchanged).
-- ---------------------------------------------------------------------------

create or replace function public.generate_recurring_tasks(p_tenant_id uuid)
returns setof public.tasks
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.can_manage_operations(p_tenant_id), false) then
    raise exception 'insufficient_privilege: cannot generate tasks for this tenant';
  end if;
  return query select * from public.job_generate_recurring_tasks(p_tenant_id);
end;
$$;

create or replace function public.escalate_overdue_tasks(p_tenant_id uuid)
returns setof public.tasks
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.can_manage_operations(p_tenant_id), false) then
    raise exception 'insufficient_privilege: cannot escalate tasks for this tenant';
  end if;
  return query select * from public.job_escalate_overdue_tasks(p_tenant_id);
end;
$$;

create or replace function public.sync_expired_documents(p_tenant_id uuid)
returns setof public.employee_documents
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.can_manage_employees(p_tenant_id), false) then
    raise exception 'insufficient_privilege: cannot sync documents for this tenant';
  end if;
  return query select * from public.job_sync_expired_documents(p_tenant_id);
end;
$$;

create or replace function public.sync_expired_compliance_records(p_tenant_id uuid)
returns setof public.compliance_records
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.can_manage_operations(p_tenant_id), false) then
    raise exception 'insufficient_privilege: cannot sync compliance records for this tenant';
  end if;
  return query select * from public.job_sync_expired_compliance_records(p_tenant_id);
end;
$$;

create or replace function public.sync_expired_qualifications(p_tenant_id uuid)
returns setof public.employee_qualifications
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.can_manage_employees(p_tenant_id), false) then
    raise exception 'insufficient_privilege: cannot sync qualifications for this tenant';
  end if;
  return query select * from public.job_sync_expired_qualifications(p_tenant_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- The runner.
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
  if p_job not in ('recurring_tasks', 'escalate_overdue', 'expire_documents', 'expire_compliance', 'expire_qualifications', 'audit_retention') then
    raise exception 'invalid_parameter: unknown job %', p_job;
  end if;

  -- Overlapping runs of the same job never work in parallel; the loser records that it skipped.
  if not pg_try_advisory_xact_lock(hashtextextended('sebetsa:job:' || p_job, 0)) then
    insert into public.job_runs (job_name, status, finished_at) values (p_job, 'skipped_locked', now());
    return jsonb_build_object('job', p_job, 'status', 'skipped_locked');
  end if;

  if p_job = 'audit_retention' then
    insert into public.job_runs (job_name, status) values (p_job, 'running') returning id into v_run;
    begin
      v_deleted := public.purge_audit_log();
      perform public.write_security_audit_event(null, null, 'audit_retention_run', 'audit_log', '00000000-0000-0000-0000-000000000000', 'success',
                                                jsonb_build_object('deleted', v_deleted, 'window', '7 years'));
      update public.job_runs set status = 'succeeded', rows_affected = v_deleted, finished_at = now() where id = v_run;
      return jsonb_build_object('job', p_job, 'status', 'succeeded', 'deleted', v_deleted);
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
      -- The sub-transaction rolled back this tenant's partial work; record it and carry on with the next tenant.
      update public.job_runs set status = 'failed', error = left(sqlerrm, 500), finished_at = now() where id = v_run;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object('job', p_job, 'status', case when v_failed = 0 then 'succeeded' else 'partial_failure' end,
                            'tenants_succeeded', v_done, 'tenants_failed', v_failed);
end;
$$;

-- Operational view for health checks and alerting: last success per job and consecutive failures.
create or replace function public.job_health()
returns table (job_name text, last_success_at timestamptz, last_status text, failures_since_success bigint)
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select r.job_name, r.status, r.started_at,
           max(r.started_at) filter (where r.status = 'succeeded') over (partition by r.job_name) as last_ok
      from public.job_runs r
     where r.status <> 'running'
  )
  select job_name,
         max(last_ok),
         (array_agg(status order by started_at desc))[1],
         count(*) filter (where status = 'failed' and (last_ok is null or started_at > last_ok))
    from ranked
   group by job_name
$$;

-- Everything below is service_role only: no browser session can start, read or alter a job.
revoke execute on function
  public.job_generate_recurring_tasks(uuid), public.job_escalate_overdue_tasks(uuid),
  public.job_sync_expired_documents(uuid), public.job_sync_expired_compliance_records(uuid),
  public.job_sync_expired_qualifications(uuid), public.run_scheduled_job(text), public.job_health()
  from public, anon, authenticated;
grant execute on function
  public.job_generate_recurring_tasks(uuid), public.job_escalate_overdue_tasks(uuid),
  public.job_sync_expired_documents(uuid), public.job_sync_expired_compliance_records(uuid),
  public.job_sync_expired_qualifications(uuid), public.run_scheduled_job(text), public.job_health()
  to service_role;

comment on function public.run_scheduled_job(text) is
  'Scheduler entry point (service_role / pg_cron only). Advisory-locked, per-tenant sub-transactions, recorded in job_runs. All jobs are idempotent.';

-- ---------------------------------------------------------------------------
-- Schedule (pg_cron). Idempotent; called by the migration when pg_cron is installed and by an operator
-- after enabling the extension (`select public.schedule_platform_jobs();`).
-- ---------------------------------------------------------------------------

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
      ('sebetsa-audit-retention',   '30 2 * * 0', 'audit_retention')
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

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform public.schedule_platform_jobs();
  end if;
end $$;
