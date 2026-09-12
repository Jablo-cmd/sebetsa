-- Sebetsa Phase K — Tasks, Duties & Operational Workflows, migration 4 of 4.
--
-- SECURITY DEFINER RPCs for lifecycle transitions, reassignment, and the
-- (manually-triggered, cron-ready-but-not-scheduled — same posture as
-- Phase H's deferred leave accrual) recurrence/escalation generators.

alter table public.tasks add column requires_evidence boolean not null default false;
comment on column public.tasks.requires_evidence is 'Denormalized from the originating task_template at generation time, or set directly on a manually-created task. complete_task() enforces at least one task_evidence row exists when true.';

-- ---------------------------------------------------------------------------
-- complete_task: assignee or manager tier. Enforces the checklist-complete
-- and evidence-required business rules server-side — never trusted from
-- the client.

create or replace function public.complete_task(p_task_id uuid)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks;
  v_is_assignee boolean;
  v_incomplete_count int;
  v_evidence_count int;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found then
    raise exception 'not_found: no task %', p_task_id;
  end if;

  select exists(select 1 from public.employees where id = v_task.assignee_id and profile_id = auth.uid()) into v_is_assignee;
  if not (v_is_assignee or public.can_manage_operations(v_task.tenant_id)) then
    raise exception 'insufficient_privilege: cannot complete this task';
  end if;

  if v_task.status not in ('open', 'in_progress', 'escalated') then
    raise exception 'invalid_task_status_transition: only an open/in_progress/escalated task can be completed (current status: %)', v_task.status;
  end if;

  select count(*) into v_incomplete_count from public.task_checklist_items where task_id = p_task_id and not is_completed;
  if v_incomplete_count > 0 then
    raise exception 'checklist_incomplete: % checklist item(s) still incomplete', v_incomplete_count;
  end if;

  if v_task.requires_evidence then
    select count(*) into v_evidence_count from public.task_evidence where task_id = p_task_id;
    if v_evidence_count = 0 then
      raise exception 'evidence_required: this task requires at least one evidence entry before it can be completed';
    end if;
  end if;

  update public.tasks set status = 'in_progress' where id = p_task_id and status = 'open';
  update public.tasks set status = 'completed' where id = p_task_id
  returning * into v_task;

  perform public.write_audit_log(v_task.tenant_id, auth.uid(), 'task_completed', 'tasks', v_task.id, null, jsonb_build_object('status', 'completed'));

  return v_task;
end;
$$;

revoke execute on function public.complete_task(uuid) from public, anon;
grant execute on function public.complete_task(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- verify_task: manager tier confirms a completed task.

create or replace function public.verify_task(p_task_id uuid)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found then
    raise exception 'not_found: no task %', p_task_id;
  end if;

  if not public.can_manage_operations(v_task.tenant_id) then
    raise exception 'insufficient_privilege: cannot verify tasks for this tenant';
  end if;

  if v_task.status <> 'completed' then
    raise exception 'invalid_task_status_transition: only a completed task can be verified (current status: %)', v_task.status;
  end if;

  update public.tasks set status = 'verified' where id = p_task_id returning * into v_task;

  perform public.write_audit_log(v_task.tenant_id, auth.uid(), 'task_verified', 'tasks', v_task.id, null, null);

  return v_task;
end;
$$;

revoke execute on function public.verify_task(uuid) from public, anon;
grant execute on function public.verify_task(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- reassign_task: manager tier only. Preserves history via the audit log
-- (before/after assignee_id) rather than a separate assignment-history
-- table — a task has one current assignee at a time, and every change is
-- already captured by tasks_audit_log/this explicit action audit.

create or replace function public.reassign_task(p_task_id uuid, p_new_assignee_id uuid, p_reason text default null)
returns public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task public.tasks;
  v_previous_assignee uuid;
begin
  select * into v_task from public.tasks where id = p_task_id for update;
  if not found then
    raise exception 'not_found: no task %', p_task_id;
  end if;

  if not public.can_manage_operations(v_task.tenant_id) then
    raise exception 'insufficient_privilege: cannot reassign tasks for this tenant';
  end if;

  if not exists (select 1 from public.employees where id = p_new_assignee_id and tenant_id = v_task.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', p_new_assignee_id, v_task.tenant_id;
  end if;

  v_previous_assignee := v_task.assignee_id;

  update public.tasks set assignee_id = p_new_assignee_id where id = p_task_id returning * into v_task;

  perform public.write_audit_log(
    v_task.tenant_id, auth.uid(), 'task_reassigned', 'tasks', v_task.id,
    jsonb_build_object('assignee_id', v_previous_assignee), jsonb_build_object('assignee_id', p_new_assignee_id, 'reason', p_reason)
  );

  return v_task;
end;
$$;

revoke execute on function public.reassign_task(uuid, uuid, text) from public, anon;
grant execute on function public.reassign_task(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- generate_recurring_tasks: manually triggered (from the UI, by a manager)
-- for now — cron-ready, not scheduled, same posture as Phase H's deferred
-- leave accrual. Creates at most one instance per template per period by
-- advancing last_generated_on, never duplicating.

create or replace function public.generate_recurring_tasks(p_tenant_id uuid)
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
  if not public.can_manage_operations(p_tenant_id) then
    raise exception 'insufficient_privilege: cannot generate tasks for this tenant';
  end if;

  for v_template in
    select * from public.task_templates
    where tenant_id = p_tenant_id and status = 'active' and recurrence_frequency is not null
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

  return;
end;
$$;

comment on function public.generate_recurring_tasks(uuid) is
  'Manually triggered from the UI by a manager — not wired to an automatic scheduler yet (cron-ready: a future pg_cron job can call this per-tenant on a schedule without any change to this function). At most one task per template per period, tracked via task_templates.last_generated_on.';

revoke execute on function public.generate_recurring_tasks(uuid) from public, anon;
grant execute on function public.generate_recurring_tasks(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- escalate_overdue_tasks: manually triggered. Escalates open/in_progress
-- tasks past their due_at and notifies the task's supervisor (reusing the
-- existing notifications infrastructure via create_notification — no new
-- notification system). Configurable-by-nature: no hard-coded grace period
-- beyond "past due_at", matching the "no meaningless notification spam"
-- principle (only overdue tasks with a supervisor on file are notified,
-- once each, on-demand rather than repeatedly).

create or replace function public.escalate_overdue_tasks(p_tenant_id uuid)
returns setof public.tasks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task record;
begin
  if not public.can_manage_operations(p_tenant_id) then
    raise exception 'insufficient_privilege: cannot escalate tasks for this tenant';
  end if;

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
      declare
        v_supervisor_profile_id uuid;
      begin
        select profile_id into v_supervisor_profile_id from public.employees where id = v_task.supervisor_id;
        if v_supervisor_profile_id is not null then
          perform public.create_notification(
            v_supervisor_profile_id, 'task_escalated', 'Task overdue: ' || v_task.title,
            'A task assigned to your team is now overdue and has been escalated.',
            p_tenant_id, 'tasks', v_task.id, null
          );
        end if;
      end;
    end if;

    perform public.write_audit_log(p_tenant_id, auth.uid(), 'task_escalated', 'tasks', v_task.id, null, jsonb_build_object('due_at', v_task.due_at));

    return next v_task;
  end loop;

  return;
end;
$$;

comment on function public.escalate_overdue_tasks(uuid) is
  'Manually triggered from the UI by a manager — cron-ready, not scheduled (same posture as generate_recurring_tasks). Escalates open/in_progress tasks past due_at and notifies the supervisor once via the existing notifications system.';

revoke execute on function public.escalate_overdue_tasks(uuid) from public, anon;
grant execute on function public.escalate_overdue_tasks(uuid) to authenticated;
