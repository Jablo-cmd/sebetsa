-- Regression suite for FND-SEC-011 (20260829260000_rate_limiting.sql):
-- check_rate_limit() and its wiring into admin_create_user (chosen as the
-- one representative provisioning RPC to exercise end-to-end — the other
-- two, admin_create_guardian/provision_employee_login, call the exact
-- same shared check_rate_limit('account_provisioning', 20, '1 hour') with
-- no per-function variation, so re-deriving the same threshold behavior
-- against each of them would test the same code path three times, not
-- three different things).
--
-- IMPORTANT ISOLATION NOTE, learned the hard way while writing this file:
-- rate_limit_events accumulates across this suite's ENTIRE run, not just
-- within one test file (there is no per-file transaction boundary) — the
-- very first version of this file pre-seeded 19 synthetic events against
-- the SHARED platform_administrator fixture (44444444...), which then
-- caused a real, unrelated, later-running test in
-- role_assignment_ladder.test.sql (that file's own legitimate
-- admin_create_user call, as that same shared actor) to fail with
-- rate_limited — a real regression this suite's own run caught. Every
-- check below that pre-seeds or exhausts the budget therefore uses a
-- fully synthetic, dedicated actor id (7f800000-...) that no other test
-- file anywhere in this suite ever uses for these three RPCs — the same
-- "dedicated fixture, never a shared one" lesson this session's own
-- attendance_alerts/fee_overdue_reminders test files already established
-- for exact-count assertions, applied here to a budget instead of a row
-- count. Only test 1 (denied before any insert happens) and test 4 (a
-- single, one-off extra event against school_owner 22222222 — negligible
-- against that actor's own account_provisioning budget across the rest
-- of the suite) reuse existing shared fixtures.

-- ---------------------------------------------------------------------------
-- 1. check_rate_limit() cannot be called directly by an authenticated
-- role — the whole point of revoking PUBLIC's default EXECUTE grant.
-- Denied before any row is ever inserted, so this is safe against any
-- shared actor.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  begin
    perform public.check_rate_limit('probe', 1, interval '1 hour');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('check_rate_limit cannot be called directly by an authenticated role', v_ok, coalesce(v_error, 'call succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- SETUP: dedicated, disposable platform-admin actors for this file's own
-- budget-exhaustion tests — is_platform_admin() (status_aware_
-- authorization.sql's redefinition) requires a REAL, active profiles row
-- to exist for auth.uid(), not just a JWT role claim, so a fully
-- synthetic actor id with no backing row fails every permission check
-- silently (discovered directly: the first version of this file used a
-- profile-less synthetic id and every admin_create_user call in it failed
-- with "insufficient_privilege: cannot create a user with role teacher",
-- not a rate-limiting failure at all). profiles.id also has a real FK to
-- auth.users(id), so both rows are required, matching the exact pattern
-- 04_employee_fixtures.sql's own "disposable" fixture already established.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '7f800000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'rate.limit.actor1@funda360.test', jsonb_build_object('role', 'platform_administrator')),
  ('00000000-0000-0000-0000-000000000000', '7f800000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'rate.limit.actor2@funda360.test', jsonb_build_object('role', 'platform_administrator'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('7f800000-0000-0000-0000-000000000001', null, 'RateLimit', 'ActorOne', 'rate.limit.actor1@funda360.test', 'platform_administrator', 'active'),
  ('7f800000-0000-0000-0000-000000000002', null, 'RateLimit', 'ActorTwo', 'rate.limit.actor2@funda360.test', 'platform_administrator', 'active');

-- ---------------------------------------------------------------------------
-- 2. A normal admin_create_user call succeeds for a dedicated synthetic
-- platform-admin actor (rate limiting does not break ordinary usage below
-- the threshold).
do $$
declare v_error text;
declare v_ok boolean := true;
declare v_email text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('7f800000-0000-0000-0000-000000000001', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('rate.limit.probe.0@schoola.test', 'Probe', 'Zero', null, 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  select email into v_email from public.profiles where email = 'rate.limit.probe.0@schoola.test';
  call test_util.record('a normal admin_create_user call still succeeds with rate limiting in place', v_ok and v_email is not null, coalesce(v_error, 'provisioned: ' || coalesce(v_email, 'null')));
end $$;

-- ---------------------------------------------------------------------------
-- 3. Pre-seed 19 more rate_limit_events for that SAME dedicated synthetic
-- actor (as the connecting superuser, bypassing RLS the same way every
-- fixture file inserts rows directly) — combined with the one real call
-- above, this actor is now at exactly 20 recorded account_provisioning
-- events. The 21st attempt must be rejected.
do $$
declare v_error text;
declare v_ok boolean := false;
declare v_email text;
begin
  insert into public.rate_limit_events (actor_profile_id, action_key)
    select '7f800000-0000-0000-0000-000000000001', 'account_provisioning' from generate_series(1, 19);

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('7f800000-0000-0000-0000-000000000001', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('rate.limit.probe.21@schoola.test', 'Probe', 'TwentyOne', null, 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'rate_limited:%';
  end;
  execute 'reset role';

  select email into v_email from public.profiles where email = 'rate.limit.probe.21@schoola.test';
  call test_util.record('the 21st account-provisioning call within the window is rejected as rate_limited', v_ok, coalesce(v_error, 'call succeeded unexpectedly'));
  call test_util.record('no user was actually provisioned by the rejected 21st call', v_email is null, 'email=' || coalesce(v_email, '(null, correctly)'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. The shared budget is per-actor, not global — a second, different
-- dedicated synthetic actor is unaffected by the first actor's exhausted
-- limit.
do $$
declare v_error text;
declare v_ok boolean := true;
declare v_email text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('7f800000-0000-0000-0000-000000000002', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('rate.limit.probe.other-actor@schoola.test', 'Probe', 'OtherActor', null, 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  select email into v_email from public.profiles where email = 'rate.limit.probe.other-actor@schoola.test';
  call test_util.record('a different actor''s own budget is unaffected by another actor''s exhausted limit', v_ok and v_email is not null, coalesce(v_error, 'provisioned: ' || coalesce(v_email, 'null')));
end $$;
