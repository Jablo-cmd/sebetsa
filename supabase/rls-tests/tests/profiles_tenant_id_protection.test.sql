-- Regression suite for the profiles.tenant_id self-service escalation fix
-- (20260803140000_prevent_direct_tenant_change.sql), plus baseline
-- tenant-isolation / role / status regression coverage so this migration's
-- new trigger is proven not to have broken anything already relied upon.
--
-- Each test impersonates a user via set_config('request.jwt.claims', ...)
-- + `set local role authenticated`, both transaction-local to the
-- enclosing `do $$ ... $$` block, so no state leaks between tests.

-- ---------------------------------------------------------------------------
-- 1. THE FIX: a user cannot change their own tenant_id directly.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set tenant_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
      where id = '11111111-1111-1111-1111-111111111111';
    call test_util.record('user cannot self-change own tenant_id', false, 'UPDATE succeeded — vulnerability still present');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('user cannot self-change own tenant_id',
      v_error like '%tenant_id can only be changed%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. current_tenant_id() is unaffected by the blocked attempt in test 1 —
-- the write never committed, so the function still resolves the original
-- tenant for that user on a fresh call.
do $$
declare
  v_tenant uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select public.current_tenant_id() into v_tenant;
  call test_util.record('current_tenant_id() unchanged after blocked attempt',
    v_tenant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'resolved tenant: ' || coalesce(v_tenant::text, 'null'));

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A platform admin cannot bypass the block either via a raw table
-- UPDATE — no SECURITY DEFINER transfer function exists yet, so this is
-- intentionally a hard block for everyone, matching the brief ("if no
-- legitimate tenant transfer functionality currently exists, completely
-- block tenant_id changes"). Confirms the fix isn't just a tenant-scoped
-- RLS check that platform admins trivially bypass.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      where id = '33333333-3333-3333-3333-333333333333';
    call test_util.record('platform admin cannot bypass tenant_id block via raw UPDATE', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('platform admin cannot bypass tenant_id block via raw UPDATE',
      v_error like '%tenant_id can only be changed%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant SELECT remains impossible (pre-existing RLS, unrelated
-- to this migration — regression check that the new trigger didn't
-- somehow affect SELECT policies).
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.profiles where tenant_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant SELECT still impossible', v_count = 0, 'visible rows from other tenant: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Regression: a user can still update their own non-sensitive columns
-- (the new trigger only fires when tenant_id itself changes).
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set first_name = 'Updated' where id = '11111111-1111-1111-1111-111111111111';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  call test_util.record('self-update of non-sensitive columns still works', v_ok, coalesce(v_error, 'first_name updated'));
  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Regression: self-status-change protection (pre-existing trigger,
-- unrelated to this fix) still blocks a user deactivating themselves.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set status = 'inactive' where id = '11111111-1111-1111-1111-111111111111';
    call test_util.record('self-status-change still blocked (pre-existing)', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('self-status-change still blocked (pre-existing)',
      v_error like '%cannot change your own account status%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Regression: role changes via the legitimate SECURITY DEFINER path
-- (admin_update_user_role) still work — proves the new tenant_id trigger
-- (which only fires on `new.tenant_id is distinct from old.tenant_id`)
-- doesn't interfere with role-only updates.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_role public.user_role;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.admin_update_user_role('11111111-1111-1111-1111-111111111111', 'principal');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select role into v_role from public.profiles where id = '11111111-1111-1111-1111-111111111111';
  call test_util.record('admin_update_user_role still works after adding tenant_id trigger',
    v_ok and v_role = 'principal', coalesce(v_error, 'role is now: ' || v_role::text));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Regression: platform functionality — admin_create_user (INSERT-based
-- provisioning, doesn't touch the new BEFORE UPDATE trigger at all) still
-- succeeds end-to-end for a platform admin.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_new_tenant uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';

  begin
    perform public.admin_create_user('new.hire@schoola.test', 'New', 'Hire', null, 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select tenant_id into v_new_tenant from public.profiles where email = 'new.hire@schoola.test';
  call test_util.record('admin_create_user still works after adding tenant_id trigger',
    v_ok and v_new_tenant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', coalesce(v_error, 'provisioned into tenant: ' || v_new_tenant::text));
end;
$$;
