-- Authorship columns are server-derived: a client cannot claim someone else
-- wrote evidence, created a task or recorded attendance.

begin;

insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-0000000f0401', 'Org I', 'active');
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000f0411', 'authenticated', 'authenticated', 'ops-i@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"operations_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000f0412', 'authenticated', 'authenticated', 'other-i@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"operations_manager"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000f0411', '00000000-0000-0000-0000-0000000f0401', 'Ops', 'I', 'ops-i@example.com', 'operations_manager', 'active'),
  ('00000000-0000-0000-0000-0000000f0412', '00000000-0000-0000-0000-0000000f0401', 'Other', 'I', 'other-i@example.com', 'operations_manager', 'active');
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000f0421', '00000000-0000-0000-0000-0000000f0401', 'Client I');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-0000000f0431', '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0421', 'Site I');
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-0000000f0441', '00000000-0000-0000-0000-0000000f0401', 'I001', 'E', 'I', current_date);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000f0411","app_metadata":{"role":"operations_manager"}}';

do $$
declare v_task uuid := gen_random_uuid(); v_who uuid;
begin
  insert into public.tasks (id, tenant_id, site_id, title, created_by)
  values (v_task, '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0431', 'T', '00000000-0000-0000-0000-0000000f0412');
  select created_by into v_who from public.tasks where id = v_task;
  if v_who <> '00000000-0000-0000-0000-0000000f0411' then raise exception 'SECURITY_FAILURE: client chose tasks.created_by (%)', v_who; end if;

  insert into public.task_evidence (tenant_id, task_id, note, submitted_by)
  values ('00000000-0000-0000-0000-0000000f0401', v_task, 'done', '00000000-0000-0000-0000-0000000f0412');
  select submitted_by into v_who from public.task_evidence where task_id = v_task;
  if v_who is distinct from '00000000-0000-0000-0000-0000000f0411' then raise exception 'FAIL: evidence submitted_by not derived from the caller (%)', v_who; end if;

  insert into public.task_comments (tenant_id, task_id, body, author_id)
  values ('00000000-0000-0000-0000-0000000f0401', v_task, 'hello', '00000000-0000-0000-0000-0000000f0412');
  select author_id into v_who from public.task_comments where task_id = v_task;
  if v_who <> '00000000-0000-0000-0000-0000000f0411' then raise exception 'SECURITY_FAILURE: client chose task_comments.author_id'; end if;
  raise notice 'PASS: tasks.created_by, task_evidence.submitted_by and task_comments.author_id are server-derived';
end $$;

do $$
declare v_rec uuid := gen_random_uuid(); v_who uuid;
begin
  insert into public.attendance_records (id, tenant_id, site_id, employee_id, status, recorded_by)
  values (v_rec, '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0431', '00000000-0000-0000-0000-0000000f0441', 'present', '00000000-0000-0000-0000-0000000f0412');
  select recorded_by into v_who from public.attendance_records where id = v_rec;
  if v_who <> '00000000-0000-0000-0000-0000000f0411' then raise exception 'SECURITY_FAILURE: client chose attendance_records.recorded_by on insert'; end if;

  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000f0412","app_metadata":{"role":"operations_manager"}}', true);
  update public.attendance_records set status = 'late', recorded_by = '00000000-0000-0000-0000-0000000f0411' where id = v_rec;
  select recorded_by into v_who from public.attendance_records where id = v_rec;
  if v_who <> '00000000-0000-0000-0000-0000000f0412' then raise exception 'SECURITY_FAILURE: a status change did not record the person who made it (%)', v_who; end if;
  raise notice 'PASS: attendance recorded_by is the person who set the status';
end $$;

reset role;
reset request.jwt.claims;
do $$
declare v_task uuid := gen_random_uuid(); v_who uuid;
begin
  -- System/service writes (no auth.uid()) keep what they supply.
  insert into public.tasks (id, tenant_id, site_id, title, created_by)
  values (v_task, '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0431', 'System task', '00000000-0000-0000-0000-0000000f0412');
  select created_by into v_who from public.tasks where id = v_task;
  if v_who <> '00000000-0000-0000-0000-0000000f0412' then raise exception 'FAIL: service-role insert should keep the supplied actor'; end if;
  raise notice 'PASS: service-role writes are not overridden';
end $$;

rollback;
