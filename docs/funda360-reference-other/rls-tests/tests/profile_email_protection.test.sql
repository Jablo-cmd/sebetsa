-- Regression suite for the profiles.email self-service escalation fix
-- (20260816100000_protect_profile_email.sql), plus baseline regression
-- coverage proving the new trigger doesn't interfere with legitimate,
-- pre-existing profile write paths.
--
-- Each test impersonates a user via set_config('request.jwt.claims', ...)
-- + `set local role authenticated`, both transaction-local to the
-- enclosing `do $$ ... $$` block, so no state leaks between tests — same
-- convention as profiles_tenant_id_protection.test.sql.

-- ---------------------------------------------------------------------------
-- 1. THE FIX: a user cannot change their own email directly.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set email = 'attacker-controlled@example.test'
      where id = '11111111-1111-1111-1111-111111111111';
    call test_util.record('user cannot self-change own email', false, 'UPDATE succeeded — vulnerability still present');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('user cannot self-change own email',
      v_error like '%email can only be changed%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. profiles.email is unchanged after the blocked attempt in test 1 — the
-- write never committed.
do $$
declare
  v_email text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select email into v_email from public.profiles where id = '11111111-1111-1111-1111-111111111111';
  call test_util.record('profiles.email unchanged after blocked attempt',
    v_email = 'teacher.a1@schoola.test', 'current email: ' || v_email);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A platform admin cannot bypass the block via a raw table UPDATE either
-- — no legitimate email-change function exists yet, so this is
-- intentionally a hard block for everyone, matching the tenant_id fix's
-- posture ("if no legitimate transfer functionality currently exists,
-- completely block the change").
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set email = 'admin-rewritten@example.test'
      where id = '33333333-3333-3333-3333-333333333333';
    call test_util.record('platform admin cannot bypass email block via raw UPDATE', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('platform admin cannot bypass email block via raw UPDATE',
      v_error like '%email can only be changed%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Regression: a user can still update their own non-sensitive columns —
-- the new trigger only fires when email itself changes.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set phone = '+27820000000' where id = '11111111-1111-1111-1111-111111111111';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  call test_util.record('self-update of non-sensitive columns still works after email trigger', v_ok, coalesce(v_error, 'phone updated'));
  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Regression: an UPDATE that re-sends the same email value (no actual
-- change) is not blocked — the trigger only fires on `is distinct from`.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.profiles set email = 'teacher.a1@schoola.test' where id = '11111111-1111-1111-1111-111111111111';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  call test_util.record('re-writing the same email value is not blocked', v_ok, coalesce(v_error, 'no-op UPDATE succeeded'));
  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Regression: role changes via the legitimate SECURITY DEFINER path
-- (admin_update_user_role) still work — proves the new email trigger
-- (which only fires on `new.email is distinct from old.email`) doesn't
-- interfere with role-only updates.
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
    perform public.admin_update_user_role('11111111-1111-1111-1111-111111111111', 'teacher');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select role into v_role from public.profiles where id = '11111111-1111-1111-1111-111111111111';
  call test_util.record('admin_update_user_role still works after adding email trigger',
    v_ok and v_role = 'teacher', coalesce(v_error, 'role is now: ' || v_role::text));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Regression: platform functionality — admin_create_user (INSERT-based
-- provisioning, doesn't touch the new BEFORE UPDATE trigger at all) still
-- succeeds end-to-end for a platform admin.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_new_email text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';

  begin
    perform public.admin_create_user('new.hire.email.test@schoola.test', 'New', 'Hire', null, 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select email into v_new_email from public.profiles where email = 'new.hire.email.test@schoola.test';
  call test_util.record('admin_create_user still works after adding email trigger',
    v_ok and v_new_email = 'new.hire.email.test@schoola.test', coalesce(v_error, 'provisioned email: ' || coalesce(v_new_email, 'null')));
end;
$$;
