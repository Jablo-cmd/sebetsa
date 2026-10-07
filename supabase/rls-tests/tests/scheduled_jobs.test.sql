-- Scheduled jobs: idempotent, service-role only, recorded, retention auditable. One transaction, rolled back.
begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000e0001', 'Org Job A', 'active'),
  ('00000000-0000-0000-0000-0000000e0002', 'Org Job B', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0011', 'authenticated', 'authenticated', 'job-admin-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0012', 'authenticated', 'authenticated', 'job-emp-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0013', 'authenticated', 'authenticated', 'job-admin-b@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000e0011', '00000000-0000-0000-0000-0000000e0001', 'Admin', 'A', 'job-admin-a@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000e0012', '00000000-0000-0000-0000-0000000e0001', 'Emp', 'A', 'job-emp-a@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000e0013', '00000000-0000-0000-0000-0000000e0002', 'Admin', 'B', 'job-admin-b@example.com', 'organization_administrator', 'active');

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000e0021', '00000000-0000-0000-0000-0000000e0001', 'Client A');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-0000000e0022', '00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0021', 'Site A');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date)
values ('00000000-0000-0000-0000-0000000e0023', '00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0012', 'J001', 'Emp', 'A', current_date);

insert into public.task_templates (id, tenant_id, site_id, title, recurrence_frequency)
values ('00000000-0000-0000-0000-0000000e0031', '00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0022', 'Daily clean', 'daily');
insert into public.tasks (id, tenant_id, site_id, assignee_id, supervisor_id, title, status, due_at)
values ('00000000-0000-0000-0000-0000000e0032', '00000000-0000-0000-0000-0000000e0001', '00000000-0000-0000-0000-0000000e0022', '00000000-0000-0000-0000-0000000e0023', '00000000-0000-0000-0000-0000000e0023', 'Overdue thing', 'open', now() - interval '2 hours');

-- Immutable audit rows can be inserted (not changed): one far past the retention window, one recent.
insert into public.audit_log (tenant_id, action, entity_table, entity_id, category, created_at)
values (null, 'ancient_event', 'tasks', gen_random_uuid(), 'business', now() - interval '9 years'),
       (null, 'recent_event', 'tasks', gen_random_uuid(), 'business', now() - interval '1 day');

-- 1. service_role runs recurring tasks twice: one task, then nothing new (idempotent / retry-safe).
set local role service_role;
do $$
declare r1 jsonb; r2 jsonb; n int;
begin
  r1 := public.run_scheduled_job('recurring_tasks');
  r2 := public.run_scheduled_job('recurring_tasks');
  select count(*) into n from public.tasks where title = 'Daily clean' and tenant_id = '00000000-0000-0000-0000-0000000e0001';
  if n <> 1 then raise exception 'FAIL: expected exactly one generated task, got %', n; end if;
  if r1->>'status' <> 'succeeded' or r2->>'status' <> 'succeeded' then raise exception 'FAIL: unexpected status % %', r1, r2; end if;
  if (select sum(rows_affected) from public.job_runs where job_name = 'recurring_tasks' and tenant_id = '00000000-0000-0000-0000-0000000e0001') <> 1 then
    raise exception 'FAIL: second run must affect 0 rows';
  end if;
  raise notice 'PASS: recurring task generation is idempotent and recorded';
end $$;

-- 2. Escalation happens once, notifies once.
do $$
declare n int; notes int;
begin
  perform public.run_scheduled_job('escalate_overdue');
  perform public.run_scheduled_job('escalate_overdue');
  perform public.run_scheduled_job('escalate_overdue');
  select count(*) into n from public.tasks where id = '00000000-0000-0000-0000-0000000e0032' and status = 'escalated';
  select count(*) into notes from public.notifications where related_entity_id = '00000000-0000-0000-0000-0000000e0032' and type = 'task_escalated';
  if n <> 1 then raise exception 'FAIL: task not escalated'; end if;
  if notes <> 1 then raise exception 'FAIL: expected exactly one escalation notification, got %', notes; end if;
  raise notice 'PASS: overdue escalation runs once, no repeated notifications';
end $$;

-- 3. Retention: purges only what is past the window and leaves an audit trail.
do $$
declare r jsonb;
begin
  r := public.run_scheduled_job('audit_retention');
  if (r->>'deleted')::int < 1 then raise exception 'FAIL: nothing purged %', r; end if;
  if exists (select 1 from public.audit_log where action = 'ancient_event') then raise exception 'FAIL: old row survived'; end if;
  if not exists (select 1 from public.audit_log where action = 'recent_event') then raise exception 'FAIL: recent row purged'; end if;
  if not exists (select 1 from public.audit_log where action = 'audit_retention_run' and category = 'security' and (metadata->>'deleted')::int >= 1) then
    raise exception 'FAIL: retention run left no security audit event';
  end if;
  raise notice 'PASS: audit retention purges only expired rows and is itself audited';
end $$;

-- 4. Unknown job and health.
do $$
begin
  begin
    perform public.run_scheduled_job('drop_everything');
    raise exception 'FAIL: unknown job accepted';
  exception when sqlstate '22023' or others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
  if (select count(*) from public.job_health()) < 3 then raise exception 'FAIL: job_health empty'; end if;
  raise notice 'PASS: unknown jobs are refused and health is reported';
end $$;

-- 5. Nobody else can run, read internals of, or purge with these.
reset role;
do $$
declare v_role text; v_fn text; v_ok boolean;
begin
  foreach v_role in array array['authenticated', 'anon'] loop
    foreach v_fn in array array['select public.run_scheduled_job(''audit_retention'')', 'select public.purge_audit_log(interval ''366 days'')',
                                'select * from public.job_generate_recurring_tasks(''00000000-0000-0000-0000-0000000e0001'')',
                                'select * from public.job_escalate_overdue_tasks(''00000000-0000-0000-0000-0000000e0001'')',
                                'select * from public.job_health()', 'select public.schedule_platform_jobs()'] loop
      v_ok := false;
      begin
        execute format('set local role %I', v_role);
        set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000e0011","app_metadata":{"role":"organization_administrator"}}';
        execute v_fn;
        v_ok := true;
      exception when insufficient_privilege then null;
      end;
      reset role;
      if v_ok then raise exception 'SECURITY_FAILURE: % could run %', v_role, v_fn; end if;
    end loop;
  end loop;
  raise notice 'PASS: job functions and purge are not executable by authenticated or anon';
end $$;

-- 6. Visibility of run history: tenant administrator sees own tenant only; employee sees nothing.
do $$
declare n int;
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000e0011', 'organization_administrator', 'aal2');
  select count(*) into n from public.job_runs where tenant_id = '00000000-0000-0000-0000-0000000e0002';
  if n <> 0 then raise exception 'SECURITY_FAILURE: admin of A sees B job runs'; end if;
  select count(*) into n from public.job_runs where tenant_id = '00000000-0000-0000-0000-0000000e0001';
  if n = 0 then raise exception 'FAIL: admin cannot see own tenant job runs'; end if;
  begin
    insert into public.job_runs (job_name, status) values ('x', 'succeeded');
    raise exception 'SECURITY_FAILURE: user wrote job_runs';
  exception when insufficient_privilege then null;
  end;
  perform test_util.as_user('00000000-0000-0000-0000-0000000e0012', 'employee', 'aal2');
  select count(*) into n from public.job_runs;
  if n <> 0 then raise exception 'SECURITY_FAILURE: employee reads job runs'; end if;
  reset role;
  raise notice 'PASS: job run history is tenant-scoped, admin-only and read-only';
end $$;

-- 7. The manager RPC still works for managers and refuses others (behaviour preserved).
do $$
declare n int;
begin
  perform test_util.as_user('00000000-0000-0000-0000-0000000e0012', 'employee', 'aal2');
  begin
    perform public.generate_recurring_tasks('00000000-0000-0000-0000-0000000e0001');
    raise exception 'SECURITY_FAILURE: employee generated tasks';
  exception when others then if sqlerrm like 'SECURITY%' then raise; end if;
  end;
  perform test_util.as_user('00000000-0000-0000-0000-0000000e0013', 'organization_administrator', 'aal2');
  begin
    perform public.escalate_overdue_tasks('00000000-0000-0000-0000-0000000e0001');
    raise exception 'SECURITY_FAILURE: other tenant admin escalated tasks';
  exception when others then if sqlerrm like 'SECURITY%' then raise; end if;
  end;
  reset role;
  raise notice 'PASS: manager RPC wrappers still enforce the caller check';
end $$;

rollback;
