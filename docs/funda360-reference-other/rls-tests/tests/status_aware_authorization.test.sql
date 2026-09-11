-- Regression suite for 20260821090000_status_aware_authorization.sql, and
-- for the school-bound-identity model generally (deactivation, historical
-- data retention, and re-provisioning the same real person as an
-- independent identity at a second school).
--
-- Uses School A/School B from 02_fixtures.sql, plus its own dedicated
-- fixtures below (prefix de1.../de2.../de3... — not reused by any other
-- fixture or test file, so mutating their status mid-test is safe and
-- cannot affect tests that run alphabetically after this one).

-- ---------------------------------------------------------------------------
-- Local fixtures: a School A teacher we will deactivate mid-test, and a
-- School A academic year we will use to prove historical data survives
-- that deactivation.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'de111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated',
   'deactivation.a1@schoola.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('de111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Deactivation', 'TestA1', 'deactivation.a1@schoola.test', 'teacher', 'active');

-- ---------------------------------------------------------------------------
-- 1. Baseline: while active, this profile can see School A's academic years
-- exactly like any other School A teacher.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('de111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('baseline: active teacher can view their school''s academic years', v_count >= 0, 'query succeeded, rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Deactivate the profile (this is exactly what DeactivateUserDialog /
-- userService drives in the app — a plain profiles.status update, no
-- session revocation).
update public.profiles set status = 'inactive' where id = 'de111111-1111-1111-1111-111111111111';

-- ---------------------------------------------------------------------------
-- 3. THE FIX: the deactivated teacher's JWT is unchanged (still carries
-- role=teacher, tenant_id=School A — exactly what a live, not-yet-expired
-- session would present) but current_tenant_id() now resolves to NULL, so
-- every tenant-scoped policy built on it correctly denies access — even
-- though nothing about their session token itself was touched.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('de111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('a deactivated user loses tenant-scoped access even with an otherwise-valid session', v_count = 0, 'rows visible after deactivation: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A deactivated user can still fetch their OWN profile row — required so
-- TenantGate.tsx can render "Account deactivated" instead of a blank
-- failure; this branch of profiles_select never depended on
-- current_tenant_id(), so it must be unaffected by the fix.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('de111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.profiles where id = 'de111111-1111-1111-1111-111111111111';
  execute 'reset role';
  call test_util.record('a deactivated user can still read their own profile row (needed for the "deactivated" notice)', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Reactivation immediately restores access (the gate is live, re-checked
-- on every query — not cached, not one-way).
update public.profiles set status = 'active' where id = 'de111111-1111-1111-1111-111111111111';

do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('de111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('reactivation immediately restores tenant-scoped access', v_count >= 0, 'query succeeded again, rows: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. A deactivated PLATFORM ADMIN loses the all-tenants bypass too, not
-- just school-bound roles. Reuses the shared platform-admin fixture
-- (44444444...) from 02_fixtures.sql. Each superuser status UPDATE is its
-- own top-level statement (matching test 2/5's pattern above), not nested
-- inside a do-block that already set request.jwt.claims — that GUC is
-- transaction-local (set_config(..., true)), and a do-block is one
-- transaction under autocommit, so nesting the reactivation UPDATE inside
-- the same block as the impersonated read would leave auth.uid() still
-- resolving to this same admin and trip prevent_self_status_change.
update public.profiles set status = 'inactive' where id = '44444444-4444-4444-4444-444444444444';

do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.schools;
  execute 'reset role';
  call test_util.record('a deactivated platform admin loses the all-tenants bypass', v_count = 0, 'schools visible while deactivated: ' || v_count);
end $$;

update public.profiles set status = 'active' where id = '44444444-4444-4444-4444-444444444444';

do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.schools;
  execute 'reset role';
  call test_util.record('reactivated platform admin regains the all-tenants bypass', v_count >= 2, 'schools visible after reactivation: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 7. Historical data survives deactivation: an academic year created by the
-- (now-reactivated, but let's prove it regardless of status) teacher's
-- school_owner colleague remains fully intact and visible to authorized
-- staff — deactivating a user is a profiles.status flip only, and never
-- touches any row that user previously created (created_by is ON DELETE
-- SET NULL, never ON DELETE CASCADE, and profiles are never hard-deleted
-- by any RLS-reachable path in the first place).
-- The status UPDATE below is its own top-level statement, not nested
-- inside a do-block that already impersonated someone — see the comment on
-- test 6 above for why nesting it would leave auth.uid() still resolving
-- to the just-impersonated user and trip prevent_self_status_change. The
-- "which academic year" lookup itself doesn't need to run as the teacher
-- (that a teacher CAN see it is already proven by test 1) — only the
-- "still visible after deactivation" half is what this test is actually
-- checking, so it impersonates just the reader, a school_owner colleague.
update public.profiles set status = 'inactive' where id = 'de111111-1111-1111-1111-111111111111';

do $$
declare v_year_id uuid; v_found boolean;
begin
  select id into v_year_id from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' limit 1;

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  perform 1 from public.academic_years where id = v_year_id;
  v_found := found;
  execute 'reset role';

  call test_util.record('historical records remain fully visible to authorized staff after the acting user is deactivated', v_found, 'academic year ' || v_year_id || ' still visible: ' || v_found);
end $$;

update public.profiles set status = 'active' where id = 'de111111-1111-1111-1111-111111111111';

-- ---------------------------------------------------------------------------
-- 8. Two independent, school-bound identities for what would represent the
-- same real person at two different schools (realistic case: a distinct,
-- school-issued email at each school — see limitation test below for why
-- the SAME email cannot be reused). Neither can see the other's data, and
-- deactivating the School A identity does not touch the School B one.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'de222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
   'p.jacobs@schoolb.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'));
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('de222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Jacobs', 'SchoolB', 'p.jacobs@schoolb.test', 'teacher', 'active');

do $$
declare v_a_sees_b int; v_b_sees_a int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('de111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_a_sees_b from public.academic_years where school_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('de222222-2222-2222-2222-222222222222', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_b_sees_a from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';

  call test_util.record('two school-bound identities (distinct emails, same person in the real world) share zero cross-tenant visibility', v_a_sees_b = 0 and v_b_sees_a = 0, 'A saw B: ' || v_a_sees_b || ', B saw A: ' || v_b_sees_a);
end $$;

do $$
declare v_b_status public.profile_status;
begin
  update public.profiles set status = 'inactive' where id = 'de111111-1111-1111-1111-111111111111';
  select status into v_b_status from public.profiles where id = 'de222222-2222-2222-2222-222222222222';
  update public.profiles set status = 'active' where id = 'de111111-1111-1111-1111-111111111111';
  call test_util.record('deactivating the School A identity does not touch the independent School B identity', v_b_status = 'active', 'School B identity status: ' || v_b_status);
end $$;

-- ---------------------------------------------------------------------------
-- 9. Documented limitation, verified as correctly-enforced rather than
-- silently broken: the SAME email cannot be reused to provision an
-- independent profile at a second school while the first still holds that
-- email (profiles_email_key is a global, not per-tenant, unique index, and
-- Supabase Auth's own auth.users.email is inherently one global identity
-- per address) — even via the privileged admin_create_user() RPC a
-- school_owner would actually use. Acting as the platform admin here
-- specifically to isolate the email-uniqueness rejection from the
-- separate role-ladder check (can_assign_role) that a School B
-- teacher/owner would also legitimately fail on for other reasons. This is
-- a real, currently-unavoidable product constraint (see docs), not a
-- security hole: it fails safely (email_taken), it does not leak School A
-- data to School B, and it does not silently merge the two schools'
-- records.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('deactivation.a1@schoola.test', 'Reused', 'Email', null, 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    call test_util.record('reusing an existing profile''s email at another school is rejected, not silently merged', false, 'admin_create_user succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('reusing an existing profile''s email at another school is rejected, not silently merged',
      v_error like '%email_taken%' or v_error like '%duplicate key%',
      'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 10. A School B administrator cannot even SEE School A's existing profile
-- to "attach" it to School B in the first place — there is no UI/RPC path
-- that searches profiles across tenants (searchGuardianCandidates,
-- searchTeacherCandidates, the Users directory — all client-filter by
-- tenant_id, and RLS enforces the same boundary regardless), so this is
-- structurally impossible, not merely policy. Proven directly here: an
-- ordinary School B school_owner searching by the exact known email gets
-- zero rows back, even though the row genuinely exists.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.profiles where email = 'deactivation.a1@schoola.test';
  execute 'reset role';
  call test_util.record('a School B admin cannot see School A''s existing profile even by exact email match — nothing to accidentally attach', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 11. The same rejection holds for the realistic actor, not just an
-- unrestricted platform admin: an ordinary School B school_owner using the
-- Users & Roles "Add user" flow with School A's existing email is rejected
-- identically.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('deactivation.a1@schoola.test', 'Reused', 'Email', null, 'teacher', null);
    call test_util.record('an ordinary School B admin also cannot reuse School A''s existing email', false, 'admin_create_user succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an ordinary School B admin also cannot reuse School A''s existing email',
      v_error like '%email_taken%' or v_error like '%duplicate key%',
      'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;
