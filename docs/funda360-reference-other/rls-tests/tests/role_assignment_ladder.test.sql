-- Regression suite for the role-assignment ladder — can_assign_role() and
-- the RPCs built on it (admin_create_user / admin_update_user_role).
-- Previously enforced at the DB layer (confirmed by reading the function
-- bodies) but never directly tested — this suite is the missing coverage,
-- not a new security control. Uses school_owner A2 (22222222) and
-- principal A1 (77777777) from 02_fixtures.sql / 04_employee_fixtures.sql
-- as the acting managers; admin_create_user calls create their own
-- disposable users each time (safe, no shared-fixture mutation risk), and
-- the "promote an existing user" tests use a dedicated local fixture
-- (ra1111...) rather than touching any shared teacher/principal fixture
-- other test files depend on staying at their original role.

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'face1111-1111-1111-1111-111111111111', 'authenticated', 'authenticated',
   'ladder.teacher@schoola.test', jsonb_build_object('role', 'teacher', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('face1111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Ladder', 'Teacher', 'ladder.teacher@schoola.test', 'teacher', 'active');

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', 'face2222-2222-2222-2222-222222222222', 'authenticated', 'authenticated',
   'ladder.principal@schoola.test', jsonb_build_object('role', 'principal', 'tenant_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('face2222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Ladder', 'Principal', 'ladder.principal@schoola.test', 'principal', 'active');

-- ---------------------------------------------------------------------------
-- 1. school_owner CAN create a new teacher.
do $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select user_id into v_id from public.admin_create_user('ladder.new.teacher@schoola.test', 'New', 'Teacher', null, 'teacher', null);
  execute 'reset role';
  call test_util.record('school_owner can create a new teacher', v_id is not null, 'created: ' || v_id);
end $$;

-- ---------------------------------------------------------------------------
-- 2. school_owner CAN create a new principal.
do $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select user_id into v_id from public.admin_create_user('ladder.new.principal@schoola.test', 'New', 'Principal', null, 'principal', null);
  execute 'reset role';
  call test_util.record('school_owner can create a new principal', v_id is not null, 'created: ' || v_id);
end $$;

-- ---------------------------------------------------------------------------
-- 3. school_owner CANNOT create an hr_manager (or any role outside
-- school_owner/principal/teacher) through this RPC — that role is
-- provisioned only via the separate employee-login-provisioning path.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('ladder.rogue.hr@schoola.test', 'Rogue', 'HR', null, 'hr_manager', null);
    call test_util.record('school_owner cannot create an hr_manager via admin_create_user', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('school_owner cannot create an hr_manager via admin_create_user',
      v_error like '%insufficient_privilege%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. school_owner CAN promote an existing teacher to principal.
do $$
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  perform public.admin_update_user_role('face1111-1111-1111-1111-111111111111', 'principal');
  execute 'reset role';
end $$;

do $$
declare v_role public.user_role;
begin
  select role into v_role from public.profiles where id = 'face1111-1111-1111-1111-111111111111';
  call test_util.record('school_owner can promote an existing teacher to principal', v_role = 'principal', 'role is now: ' || v_role);
end $$;

-- ---------------------------------------------------------------------------
-- 5. principal CAN create a new teacher.
do $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select user_id into v_id from public.admin_create_user('ladder.principal.hired@schoola.test', 'Principal', 'Hired', null, 'teacher', null);
  execute 'reset role';
  call test_util.record('principal can create a new teacher', v_id is not null, 'created: ' || v_id);
end $$;

-- ---------------------------------------------------------------------------
-- 6. principal CANNOT create a new principal — privilege escalation guard:
-- principal may only ever assign the 'teacher' role, to anyone.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('ladder.rogue.principal@schoola.test', 'Rogue', 'Principal', null, 'principal', null);
    call test_util.record('a principal cannot create another principal', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a principal cannot create another principal',
      v_error like '%insufficient_privilege%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. principal CANNOT create a school_owner either — same guard, the more
-- severe escalation.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_create_user('ladder.rogue.owner@schoola.test', 'Rogue', 'Owner', null, 'school_owner', null);
    call test_util.record('a principal cannot create a school_owner', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a principal cannot create a school_owner',
      v_error like '%insufficient_privilege%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 8. principal CANNOT touch an existing principal's role AT ALL, even to
-- "promote" them sideways to teacher — can_assign_role's principal branch
-- requires the TARGET's current role to already be teacher (or null/new).
-- Uses the dedicated ra222222 principal fixture, not the shared 77777777
-- actor or any fixture another test file depends on.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_update_user_role('face2222-2222-2222-2222-222222222222', 'teacher');
    call test_util.record('a principal cannot change another principal''s role at all', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a principal cannot change another principal''s role at all',
      v_error like '%insufficient_privilege%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 9. A platform admin is unrestricted — can create a school_owner directly
-- (the one role no school-level actor can ever assign to anyone).
do $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select user_id into v_id from public.admin_create_user('ladder.platform.owner@schoola.test', 'Platform', 'Owner', null, 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  execute 'reset role';
  call test_util.record('a platform admin can create a school_owner (unrestricted)', v_id is not null, 'created: ' || v_id);
end $$;

-- ---------------------------------------------------------------------------
-- 10. Cross-tenant: School B's owner cannot promote/manage a School A
-- user at all — can_manage_profiles(target_tenant) is checked before
-- can_assign_role even runs.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    perform public.admin_update_user_role('face1111-1111-1111-1111-111111111111', 'teacher');
    call test_util.record('School B''s owner cannot manage a School A user''s role', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s owner cannot manage a School A user''s role',
      v_error like '%insufficient_privilege%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;
