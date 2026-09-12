-- Sebetsa Phase K — Tasks, Duties & Operational Workflows: RLS/lifecycle/
-- concurrency checks.
--
--   supabase start
--   cat supabase/rls-tests/tasks_workflows.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000000a', 'Org K', 'active'),
  ('00000000-0000-0000-0000-00000000000b', 'Org L', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000001a', 'authenticated', 'authenticated', 'admin-k@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000002a', 'authenticated', 'authenticated', 'employee-k1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000003a', 'authenticated', 'authenticated', 'employee-k2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000001a', '00000000-0000-0000-0000-00000000000a', 'Admin', 'K', 'admin-k@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000002a', '00000000-0000-0000-0000-00000000000a', 'Emp', 'One', 'employee-k1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000003a', '00000000-0000-0000-0000-00000000000a', 'Emp', 'Two', 'employee-k2@example.com', 'employee', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000001a","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000004a', '00000000-0000-0000-0000-00000000000a', 'Client K');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000004a', 'Site K');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000006a', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000002a', 'K001', 'Emp', 'One', current_date),
  ('00000000-0000-0000-0000-00000000007a', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000003a', 'K002', 'Emp', 'Two', current_date);

insert into public.tasks (id, tenant_id, site_id, assignee_id, supervisor_id, title, requires_evidence)
values ('00000000-0000-0000-0000-00000000008a', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-00000000006a', '00000000-0000-0000-0000-00000000006a', 'Inspect fire extinguishers', true);

insert into public.task_checklist_items (tenant_id, task_id, label, sort_order)
values
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000008a', 'Check pressure gauges', 1),
  ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000008a', 'Check expiry dates', 2);

-- Tenant L cross-tenant target.
reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000009a', '00000000-0000-0000-0000-00000000000b', 'Client L');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000009a', 'Site L');
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-0000000000ba', '00000000-0000-0000-0000-00000000000b', 'L001', 'Other', 'TenantEmployee', current_date);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000001a","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- Cross-tenant rejection on tasks/checklist/evidence.

do $$
begin
  begin
    insert into public.tasks (tenant_id, site_id, assignee_id, title)
    values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-00000000006a', 'Cross-tenant site');
    raise exception 'SECURITY_FAILURE: cross-tenant task.site_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant task.site_id blocked (%)', sqlerrm;
  end;

  begin
    insert into public.tasks (tenant_id, site_id, assignee_id, title)
    values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-0000000000ba', 'Cross-tenant assignee');
    raise exception 'SECURITY_FAILURE: cross-tenant task.assignee_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant task.assignee_id blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Employee isolation: employee-k2 cannot see employee-k1's task.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000003a","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.tasks where id = '00000000-0000-0000-0000-00000000008a';
  if v_count <> 0 then raise exception 'FAIL: employee-k2 could read employee-k1''s task, got % rows', v_count; end if;
  raise notice 'PASS: an ordinary employee sees zero rows of a task assigned to someone else';
end $$;

do $$
begin
  begin
    perform public.complete_task('00000000-0000-0000-0000-00000000008a');
    raise exception 'SECURITY_FAILURE: employee-k2 completed a task assigned to employee-k1';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from completing another employee''s task (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- complete_task business rules: checklist must be complete, evidence
-- required when requires_evidence=true.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000002a","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.complete_task('00000000-0000-0000-0000-00000000008a');
    raise exception 'SECURITY_FAILURE: complete_task succeeded with incomplete checklist items';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: complete_task blocked while checklist items are incomplete (%)', sqlerrm;
  end;
end $$;

update public.task_checklist_items set is_completed = true where task_id = '00000000-0000-0000-0000-00000000008a';

do $$
declare v_completed_by uuid; v_completed_at timestamptz;
begin
  select completed_by, completed_at into v_completed_by, v_completed_at from public.task_checklist_items where task_id = '00000000-0000-0000-0000-00000000008a' limit 1;
  if v_completed_by <> '00000000-0000-0000-0000-00000000002a' then raise exception 'FAIL: checklist completed_by not server-derived correctly'; end if;
  if v_completed_at is null then raise exception 'FAIL: checklist completed_at was not set'; end if;
  raise notice 'PASS: checklist item completed_by/completed_at are server-derived, not client-supplied';
end $$;

do $$
begin
  begin
    perform public.complete_task('00000000-0000-0000-0000-00000000008a');
    raise exception 'SECURITY_FAILURE: complete_task succeeded with requires_evidence=true and no evidence';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: complete_task blocked without required evidence (%)', sqlerrm;
  end;
end $$;

insert into public.task_evidence (tenant_id, task_id, kind, note)
values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000008a', 'note', 'All extinguishers checked and in date.');

do $$
declare v_task public.tasks;
begin
  select * into v_task from public.complete_task('00000000-0000-0000-0000-00000000008a');
  if v_task.status <> 'completed' then raise exception 'FAIL: expected completed, got %', v_task.status; end if;
  if v_task.completed_by <> '00000000-0000-0000-0000-00000000002a' then raise exception 'FAIL: task.completed_by not server-derived correctly'; end if;
  raise notice 'PASS: complete_task succeeds once checklist is done and required evidence exists; completed_by is server-derived';
end $$;

do $$
begin
  begin
    perform public.complete_task('00000000-0000-0000-0000-00000000008a');
    raise exception 'SECURITY_FAILURE: a second complete_task call on an already-completed task succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: repeated completion on an already-completed task is blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- verify_task: manager only.

do $$
begin
  begin
    perform public.verify_task('00000000-0000-0000-0000-00000000008a');
    raise exception 'SECURITY_FAILURE: employee verified their own completed task';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from verifying a task (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000001a","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_task public.tasks;
begin
  select * into v_task from public.verify_task('00000000-0000-0000-0000-00000000008a');
  if v_task.status <> 'verified' then raise exception 'FAIL: expected verified, got %', v_task.status; end if;
  raise notice 'PASS: manager can verify a completed task';
end $$;

do $$
begin
  begin
    update public.tasks set status = 'open' where id = '00000000-0000-0000-0000-00000000008a';
    raise exception 'SECURITY_FAILURE: verified -> open transition succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: verified -> open transition rejected at the database level (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- reassign_task: manager only, cross-tenant rejected, audited.

do $$
begin
  begin
    perform public.reassign_task('00000000-0000-0000-0000-00000000008a', '00000000-0000-0000-0000-0000000000ba', 'test');
    raise exception 'SECURITY_FAILURE: reassign_task succeeded to a cross-tenant employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: reassign_task blocked for a cross-tenant employee (%)', sqlerrm;
  end;
end $$;

insert into public.tasks (id, tenant_id, site_id, assignee_id, title)
values ('00000000-0000-0000-0000-0000000000ca', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-00000000006a', 'Reassignable task');

do $$
declare v_task public.tasks; v_count int;
begin
  select * into v_task from public.reassign_task('00000000-0000-0000-0000-0000000000ca', '00000000-0000-0000-0000-00000000007a', 'employee-k1 is on leave');
  if v_task.assignee_id <> '00000000-0000-0000-0000-00000000007a' then raise exception 'FAIL: reassign_task did not update assignee_id'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'tasks' and entity_id = '00000000-0000-0000-0000-0000000000ca' and action = 'task_reassigned';
  if v_count < 1 then raise exception 'FAIL: task reassignment was not audit-logged'; end if;
  raise notice 'PASS: manager can reassign a task; reassignment is audited';
end $$;

-- ---------------------------------------------------------------------------
-- generate_recurring_tasks: idempotent per period, cross-tenant rejected.

insert into public.task_templates (id, tenant_id, site_id, title, recurrence_frequency)
values ('00000000-0000-0000-0000-0000000000da', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000005a', 'Daily opening checklist', 'daily');

do $$
begin
  begin
    perform public.generate_recurring_tasks('00000000-0000-0000-0000-00000000000b');
    raise exception 'SECURITY_FAILURE: generate_recurring_tasks succeeded against a tenant the caller does not manage';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: generate_recurring_tasks blocked for an unauthorized tenant (%)', sqlerrm;
  end;
end $$;

do $$
declare v_count int;
begin
  perform public.generate_recurring_tasks('00000000-0000-0000-0000-00000000000a');
  select count(*) into v_count from public.tasks where title = 'Daily opening checklist';
  if v_count <> 1 then raise exception 'FAIL: expected exactly 1 generated task, got %', v_count; end if;

  -- Calling it again the same day must not duplicate.
  perform public.generate_recurring_tasks('00000000-0000-0000-0000-00000000000a');
  select count(*) into v_count from public.tasks where title = 'Daily opening checklist';
  if v_count <> 1 then raise exception 'FAIL: calling generate_recurring_tasks twice in the same period duplicated the task, got %', v_count; end if;
  raise notice 'PASS: generate_recurring_tasks creates exactly one instance per period, idempotent on repeat calls';
end $$;

-- ---------------------------------------------------------------------------
-- escalate_overdue_tasks: escalates a past-due task.

insert into public.tasks (id, tenant_id, site_id, assignee_id, supervisor_id, title, due_at)
values ('00000000-0000-0000-0000-0000000000ea', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-00000000006a', '00000000-0000-0000-0000-00000000006a', 'Overdue task', now() - interval '1 hour');

do $$
declare v_status public.task_status;
begin
  perform public.escalate_overdue_tasks('00000000-0000-0000-0000-00000000000a');
  select status into v_status from public.tasks where id = '00000000-0000-0000-0000-0000000000ea';
  if v_status <> 'escalated' then raise exception 'FAIL: expected escalated, got %', v_status; end if;
  raise notice 'PASS: escalate_overdue_tasks escalates a past-due open task';
end $$;

reset role;
reset request.jwt.claims;

rollback;
