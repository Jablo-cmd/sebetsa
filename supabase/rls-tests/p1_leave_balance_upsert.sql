-- Sebetsa — regression coverage for the P1 security remediation
-- (docs/SEBETSA_REMEDIATION_REPORT.md "Remaining Risks" #3 —
-- submit_leave_request()'s plain UPDATE silently dropped the "pending"
-- figure when no leave_balances row existed yet; fixed in
-- 20260920090200_p1_leave_balance_upsert_fix.sql).
--
-- Confirmed by running this file against the pre-fix function body: the
-- FAIL-labelled assertion below (pending recorded on a genuinely
-- first-ever request, no leave_balances row pre-existing) reproducibly
-- failed (pending stayed at 0) before the fix, and passes after it.
--
--   supabase start
--   cat supabase/rls-tests/p1_leave_balance_upsert.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000ff01', 'Tenant A (leave balance upsert)', 'active'),
  ('00000000-0000-0000-0000-00000000ffa1', 'Tenant B (leave balance upsert cross-tenant)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ff02', 'authenticated', 'authenticated', 'employee-ff@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ff04', 'authenticated', 'authenticated', 'other-ff@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ff06', 'authenticated', 'authenticated', 'terminated-ff@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ff08', 'authenticated', 'authenticated', 'admin-ff@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000ff02', '00000000-0000-0000-0000-00000000ff01', 'Employee', 'One', 'employee-ff@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000ff04', '00000000-0000-0000-0000-00000000ff01', 'Other', 'Employee', 'other-ff@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000ff06', '00000000-0000-0000-0000-00000000ff01', 'Terminated', 'Employee', 'terminated-ff@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000ff08', '00000000-0000-0000-0000-00000000ff01', 'Admin', 'FF', 'admin-ff@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ff08","app_metadata":{"role":"organization_administrator"}}';

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000ff03', '00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-00000000ff02', 'FF001', 'Employee', 'One', current_date - 100),
  ('00000000-0000-0000-0000-00000000ff05', '00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-00000000ff04', 'FF002', 'Other', 'Employee', current_date - 100),
  ('00000000-0000-0000-0000-00000000ff07', '00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-00000000ff06', 'FF003', 'Terminated', 'Employee', current_date - 100);

select public.terminate_employee('00000000-0000-0000-0000-00000000ff07', current_date);

reset role;
reset request.jwt.claims;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ffa2', 'authenticated', 'authenticated', 'employee-ffa@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ffa4', 'authenticated', 'authenticated', 'admin-ffa@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000ffa2', '00000000-0000-0000-0000-00000000ffa1', 'Tenant', 'B Employee', 'employee-ffa@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-00000000ffa4', '00000000-0000-0000-0000-00000000ffa1', 'Admin', 'B', 'admin-ffa@example.com', 'organization_administrator', 'active');
-- employees rows are written by manager-tier roles only — an org admin
-- creates Tenant B's employee record, same as Tenant A's fixtures above.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ffa4","app_metadata":{"role":"organization_administrator"}}';
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-00000000ffa3', '00000000-0000-0000-0000-00000000ffa1', '00000000-0000-0000-0000-00000000ffa2', 'FFA001', 'Tenant', 'B', current_date - 100);
reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Genuinely first-ever request for this employee/leave_type/period_year —
-- no adjust_leave_balance()/recompute_leave_balance() call has ever run,
-- so no leave_balances row exists yet. This is exactly the pre-fix failure
-- case: the plain UPDATE affected zero rows and the pending figure was
-- silently lost, with no error and no visible symptom to the submitter.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ff02","app_metadata":{"role":"employee"}}';

do $$
declare
  v_leave_type_id uuid;
  v_period_year int;
  v_pending numeric;
  v_row_count int;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000ff01' and name = 'Annual';
  v_period_year := extract(year from current_date + 5)::int;

  select count(*) into v_row_count from public.leave_balances
    where tenant_id = '00000000-0000-0000-0000-00000000ff01' and employee_id = '00000000-0000-0000-0000-00000000ff03'
      and leave_type_id = v_leave_type_id and period_year = v_period_year;
  if v_row_count <> 0 then raise exception 'FAIL: test setup invariant broken — a leave_balances row already exists before the first request'; end if;

  perform public.submit_leave_request('00000000-0000-0000-0000-00000000ff03', v_leave_type_id, current_date + 5, current_date + 5, false, null, 'first ever request', null);

  select pending into v_pending from public.leave_balances
    where tenant_id = '00000000-0000-0000-0000-00000000ff01' and employee_id = '00000000-0000-0000-0000-00000000ff03'
      and leave_type_id = v_leave_type_id and period_year = v_period_year;

  if v_pending is null then raise exception 'FAIL: no leave_balances row was created by a first-ever leave request (the pre-fix bug — pending silently lost)'; end if;
  if v_pending <> 1 then raise exception 'FAIL: expected pending = 1 after a genuinely first-ever 1-day request, got %', v_pending; end if;
  raise notice 'PASS: a first-ever leave request (no pre-existing balance row) correctly records pending = %', v_pending;
end $$;

-- Duplicate/second submission: correctly accumulates (sums), never
-- destructively overwrites the figure the first request recorded.
do $$
declare
  v_leave_type_id uuid;
  v_period_year int;
  v_pending numeric;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000ff01' and name = 'Annual';
  v_period_year := extract(year from current_date + 5)::int;

  perform public.submit_leave_request('00000000-0000-0000-0000-00000000ff03', v_leave_type_id, current_date + 6, current_date + 6, false, null, 'second request, same year', null);

  select pending into v_pending from public.leave_balances
    where tenant_id = '00000000-0000-0000-0000-00000000ff01' and employee_id = '00000000-0000-0000-0000-00000000ff03'
      and leave_type_id = v_leave_type_id and period_year = v_period_year;

  if v_pending <> 2 then raise exception 'FAIL: expected pending = 2 after a second 1-day request on top of the first (sum, not overwrite), got %', v_pending; end if;
  raise notice 'PASS: a second request on the same employee/type/year accumulates pending (%) rather than overwriting it', v_pending;
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- Terminated employee: denied (unchanged control, re-confirming no
-- regression from this migration's rewrite of the function body).
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ff06","app_metadata":{"role":"employee"}}';

do $$
declare v_leave_type_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000ff01' and name = 'Annual';
  begin
    perform public.submit_leave_request('00000000-0000-0000-0000-00000000ff07', v_leave_type_id, current_date + 5, current_date + 5, false, null, 'terminated', null);
    raise exception 'SECURITY_FAILURE: a terminated employee submitted a leave request';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a terminated employee cannot submit a leave request (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- Unauthorized employee: a plain employee with no leave.approve cannot
-- submit on behalf of a different employee who is not themselves.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ff04","app_metadata":{"role":"employee"}}';

do $$
declare v_leave_type_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000ff01' and name = 'Annual';
  begin
    perform public.submit_leave_request('00000000-0000-0000-0000-00000000ff03', v_leave_type_id, current_date + 7, current_date + 7, false, null, 'unauthorized', null);
    raise exception 'SECURITY_FAILURE: an unrelated employee submitted a leave request on someone else''s behalf';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an unrelated employee cannot submit leave on someone else''s behalf (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- Cross-tenant manipulation: Tenant A's employee cannot submit a leave
-- request "for" Tenant B's employee.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ff02","app_metadata":{"role":"employee"}}';

do $$
declare v_leave_type_id uuid;
begin
  select id into v_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-00000000ffa1' and name = 'Annual';
  begin
    perform public.submit_leave_request('00000000-0000-0000-0000-00000000ffa3', v_leave_type_id, current_date + 5, current_date + 5, false, null, 'cross-tenant', null);
    raise exception 'SECURITY_FAILURE: a Tenant A employee submitted a leave request for a Tenant B employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant leave submission is denied (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
