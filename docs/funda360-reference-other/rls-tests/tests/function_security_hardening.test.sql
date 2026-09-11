-- Regression suite for 20260822000000_function_security_hardening.sql.
-- Every other test file in this suite impersonates 'authenticated' only —
-- this is the one place 'anon' (added to 00_auth_stub.sql specifically for
-- this) is exercised, since the migration's central claim is "anon loses
-- EXECUTE on every function in public; authenticated keeps it exactly
-- where the app depends on it."

-- ---------------------------------------------------------------------------
-- 1. anon cannot execute a Category 1 (RLS policy helper) function directly.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.can_view_academic('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    call test_util.record('anon cannot execute can_view_academic directly', false, 'call succeeded unexpectedly');
  exception when insufficient_privilege then
    get stacked diagnostics v_error = message_text;
    call test_util.record('anon cannot execute can_view_academic directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. anon cannot execute a Category 3 (privileged admin RPC) function.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.admin_create_user('anon.probe@schoola.test', 'Anon', 'Probe', null, 'teacher', null);
    call test_util.record('anon cannot execute admin_create_user directly', false, 'call succeeded unexpectedly');
  exception when insufficient_privilege then
    get stacked diagnostics v_error = message_text;
    call test_util.record('anon cannot execute admin_create_user directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. anon cannot execute a Category 2 (trigger) function directly either —
-- confirms the blanket revoke covers functions no test file calls by name
-- anywhere else in this suite.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.set_updated_at();
    call test_util.record('anon cannot execute the set_updated_at trigger function directly', false, 'call succeeded unexpectedly');
  exception when insufficient_privilege then
    get stacked diagnostics v_error = message_text;
    call test_util.record('anon cannot execute the set_updated_at trigger function directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. authenticated genuinely retains EXECUTE on Category 1 — a direct,
-- explicit check of the grant itself, distinct from the ~180 other tests
-- in this suite that exercise it indirectly through table queries.
do $$
declare v_result boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select public.can_view_academic('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') into v_result;
  execute 'reset role';
  call test_util.record('authenticated retains EXECUTE on can_view_academic after hardening', v_result is not null, 'call succeeded, returned: ' || v_result);
end $$;

-- ---------------------------------------------------------------------------
-- 5. authenticated retains EXECUTE on a Category 3 admin RPC — the grant
-- itself is intact; an unauthorized caller (teacher, not owner/principal)
-- still reaches the function and gets rejected by its OWN internal
-- can_assign_role() check, not a "permission denied for function" error.
-- That distinction is exactly what proves the grant, not the internal
-- logic, is what this migration changed.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('teacher.probe@schoola.test', 'Teacher', 'Probe', null, 'teacher', null);
    call test_util.record('authenticated reaches admin_create_user (grant intact); internal check still rejects an unauthorized teacher', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('authenticated reaches admin_create_user (grant intact); internal check still rejects an unauthorized teacher',
      v_error like '%insufficient_privilege%',
      'rejected by internal authorization logic, not a grant error: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Triggers still fire correctly for authenticated despite losing direct
-- EXECUTE on the trigger function — proves the central technical claim of
-- Category 2 directly, on top of the ~15 other tests in this suite that
-- already exercise trigger-guarded inserts incidentally.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.subjects (school_id, name, code) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Function Hardening Probe', 'FHP');
    call test_util.record('a trigger-guarded insert still succeeds for an authorized user despite the trigger function losing direct EXECUTE', true, 'insert succeeded, trigger fired without error');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a trigger-guarded insert still succeeds for an authorized user despite the trigger function losing direct EXECUTE', false, 'unexpected error: ' || v_error);
  end;
  execute 'reset role';
end $$;
