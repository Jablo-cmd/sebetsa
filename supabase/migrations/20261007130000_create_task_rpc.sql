-- Managers could not create ad-hoc tasks: the UI had no way to, and a client
-- doing it directly would insert the task and its checklist in two requests,
-- leaving a task with a partial checklist if the second failed.
--
-- create_task() inserts the task and its checklist in one transaction. It is
-- SECURITY INVOKER so every existing control still applies to the caller:
-- the manage-operations write policy, the restrictive site-scope policy (a
-- scoped manager can only create tasks at sites inside their scope), tenant
-- reference triggers, and the server-derived created_by.

create or replace function public.create_task(
  p_site_id           uuid,
  p_title             text,
  p_description       text default null,
  p_priority          public.task_priority default 'normal',
  p_due_at            timestamptz default null,
  p_assignee_id       uuid default null,
  p_supervisor_id     uuid default null,
  p_requires_evidence boolean default false,
  p_checklist         text[] default '{}'
) returns public.tasks
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_tenant uuid;
  v_task public.tasks;
  v_label text;
  v_order integer := 0;
begin
  select tenant_id into v_tenant from public.sites where id = p_site_id;
  if not found then
    raise exception 'not_found: no site %', p_site_id;
  end if;
  if btrim(coalesce(p_title, '')) = '' then
    raise exception 'invalid_configuration: a task needs a title';
  end if;

  insert into public.tasks (tenant_id, site_id, assignee_id, supervisor_id, title, description, priority, due_at, requires_evidence)
  values (v_tenant, p_site_id, p_assignee_id, p_supervisor_id, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''), p_priority, p_due_at, coalesce(p_requires_evidence, false))
  returning * into v_task;

  foreach v_label in array coalesce(p_checklist, '{}') loop
    if btrim(coalesce(v_label, '')) <> '' then
      v_order := v_order + 1;
      insert into public.task_checklist_items (tenant_id, task_id, label, sort_order)
      values (v_tenant, v_task.id, btrim(v_label), v_order);
    end if;
  end loop;

  return v_task;
end;
$$;

revoke execute on function public.create_task(uuid, text, text, public.task_priority, timestamptz, uuid, uuid, boolean, text[]) from public, anon;
grant execute on function public.create_task(uuid, text, text, public.task_priority, timestamptz, uuid, uuid, boolean, text[]) to authenticated;
