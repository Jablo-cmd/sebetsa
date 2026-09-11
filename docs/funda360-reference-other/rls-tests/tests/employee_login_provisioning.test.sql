-- Regression suite for provision_employee_login()/can_assign_employee_role()
-- (Sprint 2 Milestone 2 provisioning follow-up, 20260804090000). Covers the
-- caller check (can_manage_employees), the role-grant check
-- (can_assign_employee_role, deliberately independent of can_assign_role),
-- and the three data-validity rejections (already_provisioned,
-- missing_email, email_taken). Same impersonation discipline as every
-- prior test file in this harness.

-- ---------------------------------------------------------------------------
-- 1. HR Manager can provision a login for an employee with a work email
-- and an allowed role — verifies the returned user_id, the linked
-- employees.profile_id, and the seeded profiles row (name/email/role/tenant).
do $$
declare
  v_user_id uuid;
  v_temp_password text;
  v_employee_profile_id uuid;
  v_profile_first_name text;
  v_profile_role public.user_role;
  v_profile_tenant uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select user_id, temporary_password into v_user_id, v_temp_password
    from public.provision_employee_login('eeee1111-0000-0000-0000-000000000003', 'teacher', '+27 11 555 0001');

  execute 'reset role';

  select profile_id into v_employee_profile_id from public.employees where id = 'eeee1111-0000-0000-0000-000000000003';
  select first_name, role, tenant_id into v_profile_first_name, v_profile_role, v_profile_tenant
    from public.profiles where id = v_user_id;

  call test_util.record('hr_manager can provision a login for a valid employee',
    v_user_id is not null and length(v_temp_password) > 0
      and v_employee_profile_id = v_user_id
      and v_profile_first_name = 'Provision' and v_profile_role = 'teacher'
      and v_profile_tenant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    format('user_id=%s employee.profile_id=%s profile.role=%s', v_user_id, v_employee_profile_id, v_profile_role));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Principal (view-only per can_manage_employees) cannot provision.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.provision_employee_login('eeee1111-0000-0000-0000-000000000004', 'teacher', null);
    call test_util.record('provision_employee_login rejects a view-only caller', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provision_employee_login rejects a view-only caller',
      v_error like '%insufficient_privilege%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. HR Manager cannot provision a role outside can_assign_employee_role()'s
-- allowlist — 'principal' is a governance role, deliberately excluded.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.provision_employee_login('eeee1111-0000-0000-0000-000000000004', 'principal', null);
    call test_util.record('provision_employee_login rejects a non-provisionable role', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provision_employee_login rejects a non-provisionable role',
      v_error like '%insufficient_privilege%cannot provision a login with role%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Cannot provision an employee that already has a linked login
-- (eeee1111...0002, linked to teacher profile 11111111 in the fixtures).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.provision_employee_login('eeee1111-0000-0000-0000-000000000002', 'teacher', null);
    call test_util.record('provision_employee_login rejects an already-linked employee', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provision_employee_login rejects an already-linked employee',
      v_error like '%already_provisioned%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Cannot provision an employee with no work_email on file
-- (eeee1111...0001, the manager fixture — no work_email set).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.provision_employee_login('eeee1111-0000-0000-0000-000000000001', 'teacher', null);
    call test_util.record('provision_employee_login rejects an employee with no work_email', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provision_employee_login rejects an employee with no work_email',
      v_error like '%missing_email%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Cannot provision with a work_email already registered to an existing
-- login (eeee1111...0004's work_email collides with the hr_manager fixture's own email).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.provision_employee_login('eeee1111-0000-0000-0000-000000000004', 'teacher', null);
    call test_util.record('provision_employee_login rejects an already-registered email', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provision_employee_login rejects an already-registered email',
      v_error like '%email_taken%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Tenant isolation: School A's HR manager cannot provision a login for
-- a School B employee.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.provision_employee_login('eeee2222-0000-0000-0000-000000000001', 'teacher', null);
    call test_util.record('provision_employee_login rejects a cross-tenant employee', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('provision_employee_login rejects a cross-tenant employee',
      v_error like '%insufficient_privilege%', v_error);
  end;

  execute 'reset role';
end;
$$;
