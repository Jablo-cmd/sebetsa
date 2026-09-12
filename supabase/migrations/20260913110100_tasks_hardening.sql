-- Sebetsa Phase K — Tasks, Duties & Operational Workflows, migration 2 of 4.
--
-- Hardens the pre-existing tasks/task_comments (Phase 1, before the
-- Phase F cross-tenant-validation/audit-trigger pattern existed) up to the
-- same standard every other operational table now has — exactly the
-- Phase G/H/I precedent (shifts/leave_requests/attendance_records all
-- received this same treatment). Confirmed empty on hosted before this
-- migration, so backfilling triggers/columns is safe.

alter table public.tasks add column team_id uuid references public.teams (id) on delete set null;
alter table public.tasks add column completed_by uuid references public.profiles (id) on delete set null;

comment on column public.tasks.team_id is 'Optional team-level assignment, alongside (not replacing) assignee_id — a task may be assigned to a team as a whole rather than one employee.';
comment on column public.tasks.completed_by is 'Server-derived the instant status moves to completed (see tasks_validate_transition) — never client-supplied.';

create index tasks_team_id_idx on public.tasks (team_id);

create or replace function public.validate_task_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  if new.assignee_id is not null and not exists (select 1 from public.employees where id = new.assignee_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.assignee_id, new.tenant_id;
  end if;

  if new.supervisor_id is not null and not exists (select 1 from public.employees where id = new.supervisor_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.supervisor_id, new.tenant_id;
  end if;

  if new.team_id is not null and not exists (select 1 from public.teams where id = new.team_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: team % does not belong to tenant %', new.team_id, new.tenant_id;
  end if;

  return new;
end;
$$;

create trigger tasks_validate_tenant_refs
  before insert or update on public.tasks
  for each row
  execute function public.validate_task_tenant_refs();

create trigger tasks_audit_log
  after insert or update on public.tasks
  for each row
  execute function public.audit_log_from_trigger();

create or replace function public.validate_task_comment_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.tasks where id = new.task_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: task % does not belong to tenant %', new.task_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger task_comments_validate_tenant_ref
  before insert on public.task_comments
  for each row
  execute function public.validate_task_comment_tenant_ref();

-- ---------------------------------------------------------------------------
-- Lifecycle enforcement: open -> in_progress -> completed -> verified;
-- cancelled/escalated reachable from open/in_progress. completed_by/
-- completed_at are server-derived the instant status moves to completed —
-- never client-supplied, matching the actor-integrity pattern established
-- in Phase H/I.

create or replace function public.tasks_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'open' and new.status in ('in_progress', 'cancelled', 'escalated'))
    or (old.status = 'in_progress' and new.status in ('completed', 'cancelled', 'escalated'))
    or (old.status = 'escalated' and new.status in ('in_progress', 'completed', 'cancelled'))
    or (old.status = 'completed' and new.status = 'verified')
  ) then
    raise exception 'invalid_task_status_transition: % -> % is not permitted', old.status, new.status;
  end if;

  if new.status = 'completed' then
    new.completed_by := auth.uid();
    new.completed_at := now();
  end if;

  return new;
end;
$$;

create trigger tasks_validate_transition_trigger
  before update on public.tasks
  for each row
  execute function public.tasks_validate_transition();

-- ---------------------------------------------------------------------------
-- RLS: the pre-existing SELECT policy was tenant-wide (every tenant member
-- could read every task) — narrowed to the operational-management tier,
-- or the employee's own assigned/supervised task (own-employee clauses,
-- not client-supplied IDs). Write policy unchanged (manager tier only) —
-- employee self-service completion goes through complete_task() (next
-- migration), not a direct table write.

drop policy if exists tasks_select_within_tenant on public.tasks;

create policy tasks_select_own_or_broad on public.tasks for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = tasks.assignee_id and e.profile_id = auth.uid())
    or exists (select 1 from public.employees e where e.id = tasks.supervisor_id and e.profile_id = auth.uid())
    or (tasks.team_id is not null and exists (
      select 1 from public.team_members tm join public.employees e on e.id = tm.employee_id
      where tm.team_id = tasks.team_id and e.profile_id = auth.uid()
    ))
  );

comment on table public.tasks is
  'Real operational work items at a site, distinct from scheduling (a task is not itself a shift and doesn''t imply attendance). Self-service completion/checklist/evidence goes through SECURITY DEFINER RPCs, not direct table writes — tasks_write_by_manager (unchanged) remains for the operational-management tier''s direct creation/editing.';
