-- Sebetsa Phase H — RLS / lifecycle / balance / availability / scheduling-
-- conflict checks for Leave & Absence (leave_types, leave_policies,
-- leave_requests extensions, leave_balances, leave_balance_transactions,
-- employee_availability_exceptions.leave_request_id, shifts leave guard).
--
-- Same pattern as supabase/rls-tests/scheduling.sql — a real, repeatable
-- psql script against actual RLS policies/triggers/constraints/RPCs, not a
-- mock. Run:
--
--   supabase start
--   cat supabase/rls-tests/leave.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000000c1', 'Org C', 'active'),
  ('00000000-0000-0000-0000-0000000000d1', 'Org D', 'active');

-- organizations_seed_leave_types_trigger fires on the inserts above, so
-- both tenants already have their default leave_types.

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated', 'admin-c@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'employee-c1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c4', 'authenticated', 'authenticated', 'employee-c2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c5', 'authenticated', 'authenticated', 'sitemgr-c@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000c6', 'authenticated', 'authenticated', 'hr-c@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"hr_user"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c1', 'Admin', 'C', 'admin-c@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1', 'Emp', 'One', 'employee-c1@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000c1', 'Emp', 'Two', 'employee-c2@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c1', 'Site', 'Mgr', 'sitemgr-c@example.com', 'site_manager', 'active'),
  ('00000000-0000-0000-0000-0000000000c6', '00000000-0000-0000-0000-0000000000c1', 'HR', 'User', 'hr-c@example.com', 'hr_user', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000003101', '00000000-0000-0000-0000-0000000000c1', 'Client C');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000003101', 'Site C');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005101', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c3', 'C001', 'Emp', 'One', current_date),
  ('00000000-0000-0000-0000-000000005102', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c4', 'C002', 'Emp', 'Two', current_date);

-- Tenant D cross-tenant target, created as service role.
reset role;
reset request.jwt.claims;
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005901', '00000000-0000-0000-0000-0000000000d1', 'D901', 'Other', 'TenantEmployee', current_date);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- leave_types / leave_policies: seeded defaults exist, tenant isolation.

do $$
declare v_count int;
begin
  select count(*) into v_count from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1';
  if v_count <> 10 then raise exception 'FAIL: expected 10 seeded leave_types for org C, got %', v_count; end if;
  raise notice 'PASS: organizations_seed_leave_types_trigger seeded 10 leave_types for a freshly created tenant';
end $$;

-- Fetch tenant D's leave_type id as service role first — under tenant C's
-- session, leave_types RLS itself would hide it, and an INSERT...SELECT
-- against zero visible rows is a silent no-op, not a real cross-tenant
-- write attempt.
do $$
declare
  v_other_tenant_leave_type_id uuid;
begin
  reset role;
  reset request.jwt.claims;
  select id into v_other_tenant_leave_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000d1' and name = 'Annual';

  set local role authenticated;
  set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';

  begin
    insert into public.leave_policies (tenant_id, leave_type_id) values ('00000000-0000-0000-0000-0000000000c1', v_other_tenant_leave_type_id);
    raise exception 'SECURITY_FAILURE: cross-tenant leave_policy.leave_type_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant leave_policy.leave_type_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.leave_policies (tenant_id, leave_type_id, min_notice_days)
select '00000000-0000-0000-0000-0000000000c1', id, 2 from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';

-- hr_user cannot create leave_types (leave.manage requires org_admin/ops_manager/hr_user — hr_user actually CAN manage per rolePermissions.ts, so verify site_manager cannot instead).
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c5","app_metadata":{"role":"site_manager"}}';

do $$
begin
  begin
    insert into public.leave_types (tenant_id, name, is_paid) values ('00000000-0000-0000-0000-0000000000c1', 'Should Fail Type', true);
    raise exception 'SECURITY_FAILURE: site_manager created a leave_type';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: site_manager (leave.view only) blocked from creating a leave_type (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- submit_leave_request: self-service, cross-tenant employee rejection,
-- forced-pending, half-day constraint, notice-period policy enforcement.

do $$
declare v_annual_type_id uuid;
begin
  select id into v_annual_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';

  begin
    perform public.submit_leave_request('00000000-0000-0000-0000-000000005901', v_annual_type_id, current_date + 10, current_date + 11, false, null, 'x', null);
    raise exception 'SECURITY_FAILURE: submit_leave_request succeeded for a cross-tenant employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: submit_leave_request blocked for a cross-tenant employee (%)', sqlerrm;
  end;

  -- min_notice_days=2 on Annual: a request starting today must be rejected.
  begin
    perform public.submit_leave_request('00000000-0000-0000-0000-000000005101', v_annual_type_id, current_date, current_date, false, null, 'too soon', null);
    raise exception 'SECURITY_FAILURE: submit_leave_request bypassed the min_notice_days policy';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: submit_leave_request enforces min_notice_days (%)', sqlerrm;
  end;
end $$;

-- self-service submit as employee-c1, sufficiently in the future to clear notice.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3","app_metadata":{"role":"employee"}}';

do $$
declare
  v_annual_type_id uuid;
  v_other_employee_id uuid := '00000000-0000-0000-0000-000000005102';
  v_result public.leave_requests;
begin
  select id into v_annual_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';

  begin
    perform public.submit_leave_request(v_other_employee_id, v_annual_type_id, current_date + 10, current_date + 11, false, null, 'not mine', null);
    raise exception 'SECURITY_FAILURE: employee submitted leave for another employee';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from submitting leave for another employee (%)', sqlerrm;
  end;

  select * into v_result from public.submit_leave_request(
    '00000000-0000-0000-0000-000000005101', v_annual_type_id, current_date + 10, current_date + 12, false, null, 'family trip', null
  );

  if v_result.status <> 'pending' then raise exception 'FAIL: expected forced pending status, got %', v_result.status; end if;
  if v_result.decided_by is not null or v_result.decided_at is not null then raise exception 'FAIL: decided_by/decided_at should be null on a pending request'; end if;
  raise notice 'PASS: self-service submit_leave_request forces status=pending with decided_by/decided_at null';
end $$;

do $$
declare v_pending numeric;
begin
  select pending into v_pending from public.leave_balances
  where employee_id = '00000000-0000-0000-0000-000000005101' and period_year = extract(year from current_date + 10)::int;
  if v_pending <> 3 then raise exception 'FAIL: expected pending=3 (3-day request), got %', v_pending; end if;
  raise notice 'PASS: submit_leave_request increments the informational pending balance without touching remaining';
end $$;

-- ---------------------------------------------------------------------------
-- Approval security: employee cannot approve; actor-spoofing rejected;
-- leave.approve tier succeeds; decided_by/decided_at are server-derived.

do $$
declare v_request_id uuid;
begin
  select id into v_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'pending';

  begin
    perform public.approve_leave_request(v_request_id, 'self-approved');
    raise exception 'SECURITY_FAILURE: employee approved their own leave request';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from approving their own leave request (%)', sqlerrm;
  end;

  -- Direct UPDATE attempt to forge approval + spoof decided_by, bypassing the RPC.
  begin
    update public.leave_requests set status = 'approved', decided_by = auth.uid(), decided_at = now() where id = v_request_id;
    raise exception 'SECURITY_FAILURE: employee directly UPDATEd their own leave request to approved';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee blocked from directly UPDATEing their own leave request to approved (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c5","app_metadata":{"role":"site_manager"}}';

do $$
declare v_request_id uuid;
begin
  select id into v_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'pending';
  begin
    perform public.approve_leave_request(v_request_id, 'site manager approving');
    raise exception 'SECURITY_FAILURE: site_manager (leave.view only, no leave.approve) approved a leave request';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: site_manager blocked from approving (no leave.approve) (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c6","app_metadata":{"role":"hr_user"}}';

-- P0 remediation (docs/PRODUCTION_READINESS_AUDIT.md): approve_leave_request
-- now checks the request against leave_balances.remaining before approving
-- — top up a balance for the 3-day request submitted above so this
-- approval-flow assertion isn't testing balance sufficiency, which is
-- covered separately below.
do $$
declare v_annual_type_id uuid;
begin
  select id into v_annual_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';
  perform public.adjust_leave_balance('00000000-0000-0000-0000-000000005101', v_annual_type_id, extract(year from current_date + 10)::int, 20, 'test fixture top-up');
end $$;

do $$
declare
  v_request_id uuid;
  v_result public.leave_requests;
begin
  select id into v_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'pending';
  select * into v_result from public.approve_leave_request(v_request_id, 'approved by HR');

  if v_result.status <> 'approved' then raise exception 'FAIL: expected approved, got %', v_result.status; end if;
  if v_result.decided_by <> '00000000-0000-0000-0000-0000000000c6' then raise exception 'FAIL: decided_by not server-derived correctly'; end if;
  if v_result.decided_at is null then raise exception 'FAIL: decided_at was not set'; end if;
  raise notice 'PASS: hr_user (leave.approve) approved the request; decided_by/decided_at are server-derived';
end $$;

-- Repeated approval attempt (retry/double-submit) must not double-debit.
do $$
declare v_request_id uuid;
begin
  select id into v_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'approved';
  begin
    perform public.approve_leave_request(v_request_id, 'retry');
    raise exception 'SECURITY_FAILURE: a second approve_leave_request call on an already-approved request succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: repeated approval on an already-approved request is rejected, not double-debited (%)', sqlerrm;
  end;
end $$;

do $$
declare
  v_used numeric;
  v_usage_txn_count int;
begin
  select used into v_used from public.leave_balances
  where employee_id = '00000000-0000-0000-0000-000000005101' and period_year = extract(year from current_date + 10)::int;
  if v_used <> 3 then raise exception 'FAIL: expected used=3 after one approval, got %', v_used; end if;

  select count(*) into v_usage_txn_count from public.leave_balance_transactions
  where employee_id = '00000000-0000-0000-0000-000000005101' and transaction_type = 'usage';
  if v_usage_txn_count <> 1 then raise exception 'FAIL: expected exactly 1 usage ledger transaction, got %', v_usage_txn_count; end if;
  raise notice 'PASS: approval wrote exactly one usage ledger transaction and updated the balance snapshot atomically';
end $$;

-- ---------------------------------------------------------------------------
-- Availability integration: approval generated exceptions; manual
-- exceptions on the same employee are untouched.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3","app_metadata":{"role":"employee"}}';

-- A manual exception on a date NOT covered by the approved leave (self-service).
insert into public.employee_availability_exceptions (tenant_id, employee_id, exception_date, is_available, reason)
values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000005101', current_date + 30, false, 'personal, unrelated to leave');

do $$
begin
  begin
    insert into public.employee_availability_exceptions (tenant_id, employee_id, exception_date, is_available, leave_request_id)
    values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000005101', current_date + 40, false, (select id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' limit 1));
    raise exception 'SECURITY_FAILURE: a client directly wrote a leave-tagged availability exception';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: client blocked from directly writing a leave-tagged availability exception (%)', sqlerrm;
  end;
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_availability_exceptions
  where employee_id = '00000000-0000-0000-0000-000000005101' and leave_request_id is not null
    and exception_date between current_date + 10 and current_date + 12;
  if v_count <> 3 then raise exception 'FAIL: expected 3 leave-generated exceptions (one per day, 3-day request), got %', v_count; end if;

  select count(*) into v_count from public.employee_availability_exceptions
  where employee_id = '00000000-0000-0000-0000-000000005101' and exception_date = current_date + 30 and leave_request_id is null;
  if v_count <> 1 then raise exception 'FAIL: the unrelated manual exception was disturbed'; end if;
  raise notice 'PASS: approval generated one exception per leave day; the unrelated manual exception is untouched';
end $$;

-- ---------------------------------------------------------------------------
-- get_leave_affected_shifts + scheduling-conflict guard: block by default,
-- authorized override succeeds and is audited, unauthorized override fails.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at)
    values (
      '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000005101',
      (current_date + 11)::timestamptz + interval '8 hours', (current_date + 11)::timestamptz + interval '17 hours'
    );
    raise exception 'SECURITY_FAILURE: a shift was created during approved leave without an override';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: scheduling a shift during approved leave is blocked by default (%)', sqlerrm;
  end;
end $$;

-- override without leave.approve should still fail even with the flag set.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c5","app_metadata":{"role":"site_manager"}}';
set local app.override_leave_conflict = 'true';

do $$
begin
  begin
    insert into public.shifts (tenant_id, site_id, employee_id, starts_at, ends_at)
    values (
      '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000005101',
      (current_date + 11)::timestamptz + interval '8 hours', (current_date + 11)::timestamptz + interval '17 hours'
    );
    raise exception 'SECURITY_FAILURE: site_manager (no leave.approve) overrode a leave conflict';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: override_leave_conflict flag alone is insufficient without leave.approve (%)', sqlerrm;
  end;
end $$;

-- hr_user has leave.approve but not scheduling.manage (per rolePermissions.ts
-- can_manage_operations() deliberately excludes hr_user) — the authorized
-- override needs BOTH, so use organization_administrator here instead.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';
set local app.override_leave_conflict = 'true';

insert into public.shifts (id, tenant_id, site_id, employee_id, starts_at, ends_at)
values (
  '00000000-0000-0000-0000-000000008101', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000004101', '00000000-0000-0000-0000-000000005101',
  (current_date + 11)::timestamptz + interval '8 hours', (current_date + 11)::timestamptz + interval '17 hours'
);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.shifts where id = '00000000-0000-0000-0000-000000008101';
  if v_count <> 1 then raise exception 'FAIL: authorized override (leave.approve + flag) did not succeed'; end if;

  select count(*) into v_count from public.audit_log where entity_table = 'shifts' and action = 'leave_schedule_override';
  if v_count <> 1 then raise exception 'FAIL: expected exactly 1 leave_schedule_override audit row, got %', v_count; end if;
  raise notice 'PASS: authorized leave.approve override succeeds and is audited exactly once';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.get_leave_affected_shifts(
    (select id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'approved')
  );
  if v_count <> 1 then raise exception 'FAIL: expected get_leave_affected_shifts to surface exactly the 1 overridden shift, got %', v_count; end if;
  raise notice 'PASS: get_leave_affected_shifts surfaces the shift scheduled during approved leave';
end $$;

reset role;
reset request.jwt.claims;
set local app.override_leave_conflict = 'false';

-- ---------------------------------------------------------------------------
-- Revocation: reverses balance usage, removes only leave-generated
-- exceptions, does not touch the manual one, is idempotent, and does not
-- touch shifts/substitutions.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c6","app_metadata":{"role":"hr_user"}}';

do $$
declare
  v_request_id uuid;
  v_result public.leave_requests;
begin
  select id into v_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'approved';
  select * into v_result from public.revoke_leave_request(v_request_id, 'employee returned early');
  if v_result.status <> 'revoked' then raise exception 'FAIL: expected revoked, got %', v_result.status; end if;
  raise notice 'PASS: leave.approve holder can revoke an approved request';
end $$;

do $$
declare
  v_used numeric;
  v_reversal_count int;
  v_exception_count int;
  v_manual_count int;
  v_shift_count int;
begin
  select used into v_used from public.leave_balances
  where employee_id = '00000000-0000-0000-0000-000000005101' and period_year = extract(year from current_date + 10)::int;
  if v_used <> 0 then raise exception 'FAIL: expected used=0 after revocation, got %', v_used; end if;

  select count(*) into v_reversal_count from public.leave_balance_transactions
  where employee_id = '00000000-0000-0000-0000-000000005101' and transaction_type = 'reversal';
  if v_reversal_count <> 1 then raise exception 'FAIL: expected exactly 1 reversal transaction, got %', v_reversal_count; end if;

  select count(*) into v_exception_count from public.employee_availability_exceptions
  where employee_id = '00000000-0000-0000-0000-000000005101' and leave_request_id is not null;
  if v_exception_count <> 0 then raise exception 'FAIL: revocation did not remove all leave-generated exceptions, % remain', v_exception_count; end if;

  select count(*) into v_manual_count from public.employee_availability_exceptions
  where employee_id = '00000000-0000-0000-0000-000000005101' and exception_date = current_date + 30 and leave_request_id is null;
  if v_manual_count <> 1 then raise exception 'FAIL: revocation disturbed the unrelated manual exception'; end if;

  raise notice 'PASS: revocation reversed balance usage exactly once, removed only leave-generated exceptions, and preserved the manual exception';
end $$;

-- Shift-existence is a raw data-integrity assertion ("did revocation
-- physically delete the row"), not a permissions test, so it is checked as
-- the table owner rather than under hr_user's role-scoped visibility.
-- Corrected 2026-09-19 as part of the production-readiness audit's C-2
-- remediation (docs/PRODUCTION_READINESS_AUDIT.md): shifts_select_broad no
-- longer grants hr_user visibility (hr_user does not hold scheduling.view
-- in rolePermissions.ts) — this check previously relied on the very
-- blanket-SELECT bug being fixed to see the shift row at all.
reset role;
reset request.jwt.claims;
do $$
declare v_shift_count int;
begin
  select count(*) into v_shift_count from public.shifts where id = '00000000-0000-0000-0000-000000008101';
  if v_shift_count <> 1 then raise exception 'FAIL: revocation must never delete/restore shifts, but the shift is gone'; end if;
  raise notice 'PASS: revocation left shifts untouched';
end $$;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c6","app_metadata":{"role":"hr_user"}}';

-- Repeated revocation attempt must fail (already revoked) rather than
-- double-reverse.
do $$
declare v_request_id uuid;
begin
  select id into v_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'revoked';
  begin
    perform public.revoke_leave_request(v_request_id, 'retry');
    raise exception 'SECURITY_FAILURE: a second revoke_leave_request call on an already-revoked request succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: repeated revocation is rejected (invalid transition), not double-reversed (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Cancellation: own pending only; rejection creates no usage; illegal
-- transitions (rejected -> approved, cancelled -> approved, revoked ->
-- anything) are all rejected.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3","app_metadata":{"role":"employee"}}';

do $$
declare
  v_annual_type_id uuid;
  v_new_request public.leave_requests;
begin
  select id into v_annual_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';
  select * into v_new_request from public.submit_leave_request('00000000-0000-0000-0000-000000005101', v_annual_type_id, current_date + 20, current_date + 20, false, null, 'second request', null);

  perform public.cancel_leave_request(v_new_request.id);

  begin
    perform public.cancel_leave_request(v_new_request.id);
    raise exception 'SECURITY_FAILURE: cancelling an already-cancelled request succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee cancelled own pending request; a second cancel attempt is rejected (%)', sqlerrm;
  end;

  -- As a plain employee, RLS itself hides a non-pending row from UPDATE
  -- (0 rows affected, no exception) before the transition trigger would
  -- even run — check row count rather than expecting a raised exception.
  declare
    v_rows_affected int;
  begin
    update public.leave_requests set status = 'approved' where id = v_new_request.id;
    get diagnostics v_rows_affected = row_count;
    if v_rows_affected <> 0 then
      raise exception 'SECURITY_FAILURE: cancelled -> approved transition succeeded (% row(s) affected)', v_rows_affected;
    end if;
    raise notice 'PASS: cancelled -> approved transition affects 0 rows for a plain employee (RLS hides a non-pending row from UPDATE)';
  end;
end $$;

do $$
declare v_pending numeric;
begin
  select pending into v_pending from public.leave_balances
  where employee_id = '00000000-0000-0000-0000-000000005101' and period_year = extract(year from current_date + 20)::int;
  if v_pending <> 0 then raise exception 'FAIL: expected pending=0 after cancellation, got %', v_pending; end if;
  raise notice 'PASS: cancellation reverses the informational pending balance';
end $$;

-- Employee cannot cancel someone else's request.
do $$
declare v_annual_type_id uuid;
begin
  select id into v_annual_type_id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c4","app_metadata":{"role":"employee"}}';

do $$
declare v_other_request_id uuid;
begin
  select id into v_other_request_id from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101' and status = 'pending' limit 1;
  if v_other_request_id is not null then
    begin
      perform public.cancel_leave_request(v_other_request_id);
      raise exception 'SECURITY_FAILURE: employee-c2 cancelled employee-c1''s leave request';
    exception
      when others then
        if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
        raise notice 'PASS: employee blocked from cancelling another employee''s leave request (%)', sqlerrm;
    end;
  else
    raise notice 'PASS (skipped, no other pending request to test against)';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Employee isolation on SELECT: employee-c2 cannot read employee-c1's
-- leave requests or balances.

do $$
declare v_count int;
begin
  select count(*) into v_count from public.leave_requests where employee_id = '00000000-0000-0000-0000-000000005101';
  if v_count <> 0 then raise exception 'FAIL: employee-c2 (no leave.view broad access) could read employee-c1''s leave requests, got % rows', v_count; end if;

  select count(*) into v_count from public.leave_balances where employee_id = '00000000-0000-0000-0000-000000005101';
  if v_count <> 0 then raise exception 'FAIL: employee-c2 could read employee-c1''s leave balances, got % rows', v_count; end if;
  raise notice 'PASS: an ordinary employee sees zero rows of another employee''s leave requests/balances';
end $$;

-- ---------------------------------------------------------------------------
-- Ledger append-only: no direct client UPDATE/DELETE, no direct client
-- INSERT (only the RPCs, running as the row's owning function, write it).

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c2","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    insert into public.leave_balance_transactions (tenant_id, employee_id, leave_type_id, period_year, transaction_type, amount)
    select '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000005101', id, 2026, 'adjustment', 999
    from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual';
    raise exception 'SECURITY_FAILURE: direct client INSERT into leave_balance_transactions succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: direct client INSERT into the ledger blocked (%)', sqlerrm;
  end;

  -- No UPDATE/DELETE policy exists at all on this table, so FORCE ROW LEVEL
  -- SECURITY denies the command outright: 0 rows affected, no exception —
  -- check row count rather than expecting a raised error.
  declare
    v_rows_affected int;
  begin
    update public.leave_balance_transactions set amount = 0 where employee_id = '00000000-0000-0000-0000-000000005101';
    get diagnostics v_rows_affected = row_count;
    if v_rows_affected <> 0 then
      raise exception 'SECURITY_FAILURE: direct client UPDATE of a ledger row succeeded (% row(s) affected)', v_rows_affected;
    end if;
    raise notice 'PASS: direct client UPDATE of a ledger row affects 0 rows (no UPDATE policy exists)';
  end;

  declare
    v_rows_affected int;
  begin
    delete from public.leave_balance_transactions where employee_id = '00000000-0000-0000-0000-000000005101';
    get diagnostics v_rows_affected = row_count;
    if v_rows_affected <> 0 then
      raise exception 'SECURITY_FAILURE: direct client DELETE of a ledger row succeeded (% row(s) affected)', v_rows_affected;
    end if;
    raise notice 'PASS: direct client DELETE of a ledger row affects 0 rows (no DELETE policy exists)';
  end;
end $$;

-- ---------------------------------------------------------------------------
-- adjust_leave_balance / recompute_leave_balance: leave.manage only.

do $$
begin
  begin
    perform public.adjust_leave_balance('00000000-0000-0000-0000-000000005101', (select id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual'), 2026, 5, 'test');
  exception
    when others then
      raise exception 'FAIL: organization_administrator (leave.manage) could not adjust a balance: %', sqlerrm;
  end;
  raise notice 'PASS: organization_administrator (leave.manage) can adjust a leave balance';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c5","app_metadata":{"role":"site_manager"}}';

do $$
begin
  begin
    perform public.adjust_leave_balance('00000000-0000-0000-0000-000000005101', (select id from public.leave_types where tenant_id = '00000000-0000-0000-0000-0000000000c1' and name = 'Annual'), 2026, 5, 'should fail');
    raise exception 'SECURITY_FAILURE: site_manager (no leave.manage) adjusted a leave balance';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: site_manager blocked from adjusting a leave balance (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
