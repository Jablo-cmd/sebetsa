-- Sebetsa — regression coverage for the P0 security remediation
-- (docs/PRODUCTION_READINESS_AUDIT.md Critical findings C-3 and C-5, and
-- the High "self-approval" findings; fixed in
-- 20260919090200_p0_terminated_employee_access_revocation.sql,
-- 20260919090300_p0_site_assignment_enforcement.sql and
-- 20260919090400_p0_self_approval_guards.sql).
--
-- Confirmed by running this file against the pre-fix migration set: every
-- SECURITY_FAILURE-labelled assertion below reproducibly failed (the
-- attack succeeded) before the fix, and passes after it. See
-- docs/SEBETSA_REMEDIATION_REPORT.md for the full before/after record.
--
--   supabase start
--   cat supabase/rls-tests/p0_termination_and_self_approval.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000e9a1', 'Org G (termination/self-approval)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e9a2', 'authenticated', 'authenticated', 'admin-g@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e9a3', 'authenticated', 'authenticated', 'hr-g@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"hr_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000e9a4', 'authenticated', 'authenticated', 'terminated-g@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000e9a2', '00000000-0000-0000-0000-00000000e9a1', 'Admin', 'G', 'admin-g@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000e9a3', '00000000-0000-0000-0000-00000000e9a1', 'HR', 'G', 'hr-g@example.com', 'hr_user', 'active'),
  ('00000000-0000-0000-0000-00000000e9a4', '00000000-0000-0000-0000-00000000e9a1', 'Terminated', 'Employee', 'terminated-g@example.com', 'employee', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a2","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-00000003e9a1', '00000000-0000-0000-0000-00000000e9a1', 'Client G');
insert into public.sites (id, tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000004e9a1', '00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000003e9a1', 'Site G', 'active');
insert into public.sites (id, tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000004e9a2', '00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000003e9a1', 'Onboarding Site G', 'onboarding');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000005e9a1', '00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000000e9a4', 'G001', 'Terminated', 'Employee', current_date - 30);
insert into public.site_assignments (tenant_id, site_id, employee_id) values
  ('00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000004e9a1', '00000000-0000-0000-0000-00000005e9a1');

-- Confirm the employee can operate normally while still active (control,
-- proves the later denial is caused by termination, not some unrelated gap).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a4","app_metadata":{"role":"employee"}}';

do $$
declare v_record public.attendance_records;
begin
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000005e9a1', '00000000-0000-0000-0000-00000004e9a1');
  if v_record.id is null then raise exception 'FAIL: active employee could not clock in (control case)'; end if;
  perform public.clock_out(v_record.id);
  raise notice 'PASS: active employee can clock in/out normally (control)';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- C-3: terminate_employee() must revoke self-service access.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a2","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_result public.employees;
begin
  select * into v_result from public.terminate_employee('00000000-0000-0000-0000-00000005e9a1', current_date);
  if v_result.employment_status <> 'terminated' then raise exception 'FAIL: terminate_employee did not set employment_status'; end if;
  raise notice 'PASS: employee terminated';
end $$;

reset role;
reset request.jwt.claims;

-- Terminated employee: clock-in.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a4","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.clock_in('00000000-0000-0000-0000-00000005e9a1', '00000000-0000-0000-0000-00000004e9a1');
    raise exception 'SECURITY_FAILURE: terminated employee clocked in';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: terminated employee cannot clock in (%)', sqlerrm;
  end;
end $$;

-- Terminated employee: submit_leave_request.
do $$
declare v_leave_type_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000e9a1' and name = 'Annual';
  begin
    perform public.submit_leave_request('00000000-0000-0000-0000-00000005e9a1', v_leave_type_id, current_date + 5, current_date + 5, false, null, 'test', null);
    raise exception 'SECURITY_FAILURE: terminated employee submitted a leave request';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: terminated employee cannot submit a leave request (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- terminate_employee must not be reachable by a manager trying to
-- assign/clock-in the terminated employee either (not just self-service).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a3","app_metadata":{"role":"hr_user"}}';

do $$
begin
  begin
    perform public.clock_in('00000000-0000-0000-0000-00000005e9a1', '00000000-0000-0000-0000-00000004e9a1');
    raise exception 'SECURITY_FAILURE: a manager clocked in a terminated employee on their behalf';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a manager cannot clock in a terminated employee either (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- C-5: site_assignments enforcement — terminated employee, inactive site.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a2","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    insert into public.site_assignments (tenant_id, site_id, employee_id) values
      ('00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000004e9a1', '00000000-0000-0000-0000-00000005e9a1');
    raise exception 'SECURITY_FAILURE: a terminated employee was assigned to a new site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a terminated employee cannot receive a new site assignment (%)', sqlerrm;
  end;
end $$;

-- Reactivate, then confirm an inactive (onboarding) site is still rejected.
do $$
begin
  perform public.reactivate_employee('00000000-0000-0000-0000-00000005e9a1');
end $$;

do $$
begin
  begin
    insert into public.site_assignments (tenant_id, site_id, employee_id) values
      ('00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000004e9a2', '00000000-0000-0000-0000-00000005e9a1');
    raise exception 'SECURITY_FAILURE: an active employee was assigned to a non-active (onboarding) site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an assignment to a non-active site is rejected (%)', sqlerrm;
  end;
end $$;

-- Reactivation genuinely restores self-service access.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a4","app_metadata":{"role":"employee"}}';

do $$
declare v_record public.attendance_records;
begin
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000005e9a1', '00000000-0000-0000-0000-00000004e9a1');
  if v_record.id is null then raise exception 'FAIL: reactivated employee could not clock in'; end if;
  perform public.clock_out(v_record.id);
  raise notice 'PASS: reactivated employee can clock in/out again';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Self-approval: leave and attendance-correction (compliance/task/incident
-- self-approval regressions live in their own domain test files, updated
-- alongside this remediation — see compliance_incidents.sql).

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000e9a2","app_metadata":{"role":"organization_administrator"}}';

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000005e9a2', '00000000-0000-0000-0000-00000000e9a1', '00000000-0000-0000-0000-00000000e9a2', 'G002', 'Manager', 'Self', current_date - 100);

do $$
declare v_leave_type_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000e9a1' and name = 'Annual';
  perform public.adjust_leave_balance('00000000-0000-0000-0000-00000005e9a2', v_leave_type_id, extract(year from current_date + 5)::int, 20, 'test fixture top-up');
end $$;

do $$
declare
  v_leave_type_id uuid;
  v_request_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000e9a1' and name = 'Annual';
  select id into v_request_id from public.submit_leave_request('00000000-0000-0000-0000-00000005e9a2', v_leave_type_id, current_date + 5, current_date + 5, false, null, 'self', null);

  begin
    perform public.approve_leave_request(v_request_id, 'self-approving');
    raise exception 'SECURITY_FAILURE: organization_administrator approved their own leave request';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: organization_administrator cannot approve their own leave request (%)', sqlerrm;
  end;
end $$;

do $$
declare v_record public.attendance_records;
begin
  select * into v_record from public.clock_in('00000000-0000-0000-0000-00000005e9a2', '00000000-0000-0000-0000-00000004e9a1');
  perform public.clock_out(v_record.id);

  declare v_correction_id uuid;
  begin
    select id into v_correction_id from public.request_attendance_correction(v_record.id, 'clock_out_at', (now() + interval '1 hour')::text, 'self correction');
    begin
      perform public.decide_attendance_correction(v_correction_id, true, 'self-approving');
      raise exception 'SECURITY_FAILURE: organization_administrator approved their own attendance correction';
    exception
      when others then
        if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
        raise notice 'PASS: organization_administrator cannot approve their own attendance correction (%)', sqlerrm;
    end;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
