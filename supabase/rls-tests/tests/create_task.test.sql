-- create_task(): one-transaction task + checklist, under the caller's own RLS and scope.

begin;

insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-0000000f0601', 'Org L', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, crypt('x', gen_salt('bf')), now(), jsonb_build_object('role', u.role), '{}', now(), now()
from (values
  ('00000000-0000-0000-0000-0000000f0611', 'ops-l@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0612', 'sm-l@example.com', 'site_manager'),
  ('00000000-0000-0000-0000-0000000f0613', 'emp-l@example.com', 'employee')
) as u(id, email, role);

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status)
select p.id::uuid, '00000000-0000-0000-0000-0000000f0601', p.f, 'L', p.email, p.role::public.user_role, 'active'
from (values
  ('00000000-0000-0000-0000-0000000f0611', 'Ops', 'ops-l@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0612', 'Site', 'sm-l@example.com', 'site_manager'),
  ('00000000-0000-0000-0000-0000000f0613', 'Emp', 'emp-l@example.com', 'employee')
) as p(id, f, email, role);

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000f0621', '00000000-0000-0000-0000-0000000f0601', 'Client L');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-0000000f0631', '00000000-0000-0000-0000-0000000f0601', '00000000-0000-0000-0000-0000000f0621', 'Site L1'),
  ('00000000-0000-0000-0000-0000000f0632', '00000000-0000-0000-0000-0000000f0601', '00000000-0000-0000-0000-0000000f0621', 'Site L2');
insert into public.user_scopes (tenant_id, profile_id, scope_type, scope_id)
values ('00000000-0000-0000-0000-0000000f0601', '00000000-0000-0000-0000-0000000f0612', 'site', '00000000-0000-0000-0000-0000000f0631');

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0611","app_metadata":{"role":"operations_manager"}}';

do $$
declare v_task public.tasks; v_labels text[]; v_creator uuid;
begin
  v_task := public.create_task('00000000-0000-0000-0000-0000000f0631', '  Clean lobby  ', 'Daily', 'high', now() + interval '1 day', null, null, true,
                               array['Mop', '   ', 'Disinfect handles']);
  if v_task.title <> 'Clean lobby' or v_task.priority <> 'high' or not v_task.requires_evidence or v_task.status <> 'open' then
    raise exception 'FAIL: unexpected task %', to_jsonb(v_task);
  end if;
  if v_task.created_by is distinct from '00000000-0000-0000-0000-0000000f0611'::uuid then raise exception 'FAIL: created_by must be the caller, got %', v_task.created_by; end if;
  select array_agg(label order by sort_order) into v_labels from public.task_checklist_items where task_id = v_task.id;
  if v_labels <> array['Mop', 'Disinfect handles'] then raise exception 'FAIL: checklist %', v_labels; end if;

  begin
    perform public.create_task('00000000-0000-0000-0000-0000000f0631', '   ');
    raise exception 'SECURITY_FAILURE: a blank title was accepted';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'invalid_configuration%' then raise exception 'FAIL: expected invalid_configuration, got %', sqlerrm; end if;
  end;
  begin
    perform public.create_task('00000000-0000-0000-0000-0000000f0699', 'Nowhere');
    raise exception 'SECURITY_FAILURE: a task was created for a non-existent site';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'not_found%' then raise exception 'FAIL: expected not_found, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: create_task creates the task and its checklist together, as the caller';
end $$;

-- A scoped site manager can create tasks only inside their scope.
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0612","app_metadata":{"role":"site_manager"}}', true);
do $$
declare v_task public.tasks;
begin
  v_task := public.create_task('00000000-0000-0000-0000-0000000f0631', 'In scope');
  begin
    perform public.create_task('00000000-0000-0000-0000-0000000f0632', 'Out of scope');
    raise exception 'SECURITY_FAILURE: a scoped manager created a task outside their scope';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
  end;
  if exists (select 1 from public.tasks where title = 'Out of scope') then raise exception 'FAIL: out-of-scope task exists'; end if;
  raise notice 'PASS: scope limits where a manager can create tasks';
end $$;

-- An employee cannot create tasks at all.
select set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0613","app_metadata":{"role":"employee"}}', true);
do $$
begin
  begin
    perform public.create_task('00000000-0000-0000-0000-0000000f0631', 'Self-assigned');
    raise exception 'SECURITY_FAILURE: an employee created a task';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
  end;
  raise notice 'PASS: employees cannot create tasks';
end $$;

rollback;
