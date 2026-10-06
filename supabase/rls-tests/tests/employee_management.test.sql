-- Regression suite for Sprint 2 Milestone 2 Phase 1 (Employee Management
-- database layer): view/manage role split, self-access, tenant isolation,
-- both tenant-match triggers, the reporting-cycle guard, terminate/
-- reactivate RPCs, no-hard-delete, and created_by/updated_by population.
-- Same impersonation discipline as every prior test file in this harness.

-- ---------------------------------------------------------------------------
-- 1. HR Manager (manage) can view the employee directory for their own school.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  -- 6, not the original 4 — 06_employee_provisioning_fixtures.sql added two
  -- more School A employees for the provisioning regression suite.
  select count(*) into v_count from public.employees where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('HR manager can view own school employee directory', v_count = 6, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Principal (view only, per access matrix) can view the directory but cannot create.
do $$
declare
  v_count int;
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  -- 6, not the original 4 — see the count-1 test above for why.
  select count(*) into v_count from public.employees where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  begin
    insert into public.employees (school_id, employee_number, first_name, last_name, hire_date)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EMP-A999', 'Should', 'Fail', '2026-01-01');
    call test_util.record('principal can view but not create employees', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('principal can view but not create employees', v_count = 6, 'view rows=' || v_count || ', insert blocked: ' || v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Teacher (self only): cannot see the directory, CAN see their own linked employee record.
do $$
declare
  v_directory_count int;
  v_own_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_directory_count from public.employees where id = 'eeee1111-0000-0000-0000-000000000001';
  select count(*) into v_own_count from public.employees where id = 'eeee1111-0000-0000-0000-000000000002';

  call test_util.record('teacher cannot view others but can view own linked employee record',
    v_directory_count = 0 and v_own_count = 1, 'others=' || v_directory_count || ' own=' || v_own_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Tenant isolation: School B's teacher cannot see School A's employees.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.employees where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant employees are invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. department_id tenant-match trigger: HR Manager (School A) cannot
-- reference School B's department.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.employees (school_id, department_id, employee_number, first_name, last_name, hire_date)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'dddd2222-0000-0000-0000-000000000001', 'EMP-A900', 'Cross', 'Tenant', '2026-01-01');
    call test_util.record('employees.department_id must match own school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('employees.department_id must match own school',
      v_error like '%department_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. reports_to_employee_id tenant-match trigger: cannot reference a School B employee.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.employees (school_id, employee_number, first_name, last_name, hire_date, reports_to_employee_id)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EMP-A901', 'Cross', 'Report', '2026-01-01', 'eeee2222-0000-0000-0000-000000000001');
    call test_util.record('reports_to_employee_id must match own school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('reports_to_employee_id must match own school',
      v_error like '%reports_to_employee_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Direct self-reference blocked by the check constraint.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.employees set reports_to_employee_id = id where id = 'eeee1111-0000-0000-0000-000000000001';
    call test_util.record('direct self-reporting is blocked', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('direct self-reporting is blocked',
      v_error like '%employees_no_self_report%' or v_error like '%reporting cycle%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Reporting-cycle detection: eeee1111...0001 already manages
-- eeee1111...0002 (fixture). Attempting to make 0001 report to 0002 would
-- close a 2-hop cycle and must be rejected.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.employees set reports_to_employee_id = 'eeee1111-0000-0000-0000-000000000002'
      where id = 'eeee1111-0000-0000-0000-000000000001';
    call test_util.record('reporting cycles are rejected', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('reporting cycles are rejected',
      v_error like '%reporting cycle%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. terminate_employee cascades to the linked profile's status.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_employment_status public.employment_status;
  v_profile_status public.profile_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.terminate_employee('eeee1111-0000-0000-0000-000000000098', '2026-06-01');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select employment_status into v_employment_status from public.employees where id = 'eeee1111-0000-0000-0000-000000000098';
  select status into v_profile_status from public.profiles where id = '99999999-9999-9999-9999-999999999998';

  call test_util.record('terminate_employee cascades to linked profile status',
    v_ok and v_employment_status = 'terminated' and v_profile_status = 'inactive',
    coalesce(v_error, format('employment=%s profile=%s', v_employment_status, v_profile_status)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. terminate_employee rejects a caller without employee.manage (Principal, view-only).
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.terminate_employee('eeee1111-0000-0000-0000-000000000001', '2026-06-01');
    call test_util.record('terminate_employee rejects a view-only caller', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('terminate_employee rejects a view-only caller',
      v_error like '%insufficient_privilege%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. reactivate_employee does NOT reactivate the linked profile's status
-- (asymmetric on purpose).
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_employment_status public.employment_status;
  v_profile_status public.profile_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.reactivate_employee('eeee1111-0000-0000-0000-000000000098');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select employment_status into v_employment_status from public.employees where id = 'eeee1111-0000-0000-0000-000000000098';
  select status into v_profile_status from public.profiles where id = '99999999-9999-9999-9999-999999999998';

  call test_util.record('reactivate_employee does not touch linked profile status',
    v_ok and v_employment_status = 'active' and v_profile_status = 'inactive',
    coalesce(v_error, format('employment=%s profile(still inactive)=%s', v_employment_status, v_profile_status)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Employees cannot be hard-deleted (no DELETE policy).
do $$
declare
  v_count_before int;
  v_count_after int;
begin
  select count(*) into v_count_before from public.employees where id = 'eeee1111-0000-0000-0000-000000000001';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.employees where id = 'eeee1111-0000-0000-0000-000000000001';
  execute 'reset role';

  select count(*) into v_count_after from public.employees where id = 'eeee1111-0000-0000-0000-000000000001';
  call test_util.record('employees cannot be hard-deleted (no DELETE policy)',
    v_count_before = 1 and v_count_after = 1, format('before=%s after=%s', v_count_before, v_count_after));
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. created_by/updated_by are populated from the acting user, not left null.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_created_by uuid;
  v_updated_by uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.employees (id, school_id, employee_number, first_name, last_name, hire_date)
      values ('eeee1111-0000-0000-0000-000000000009', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EMP-A909', 'Audit', 'Check', '2026-01-01');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select created_by, updated_by into v_created_by, v_updated_by from public.employees where id = 'eeee1111-0000-0000-0000-000000000009';
  call test_util.record('created_by/updated_by are populated from the acting user',
    v_ok and v_created_by = '88888888-8888-8888-8888-888888888888' and v_updated_by = '88888888-8888-8888-8888-888888888888',
    coalesce(v_error, format('created_by=%s updated_by=%s', v_created_by, v_updated_by)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. profile_id is ON DELETE SET NULL, not CASCADE — the employee record
-- survives deletion of its linked profile (and the auth.users row it
-- references, cascading from there per Milestone 3's own FK). Uses the
-- dedicated disposable fixture (eeee1111...0099 / 99999999...), not a
-- shared one, since this test is destructive.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_count int;
  v_profile_id uuid;
begin
  begin
    delete from auth.users where id = '99999999-9999-9999-9999-999999999999';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  select count(*), profile_id into v_count, v_profile_id from public.employees where id = 'eeee1111-0000-0000-0000-000000000099' group by profile_id;

  call test_util.record('employee record survives profile/auth-user deletion (ON DELETE SET NULL)',
    v_ok and v_count = 1 and v_profile_id is null,
    coalesce(v_error, format('rows=%s profile_id now=%s', v_count, v_profile_id)));
end;
$$;
