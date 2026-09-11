-- Regression suite for the `schools` table itself — previously covered
-- only indirectly through other domains' fixtures. Uses School A/B and
-- their users from 02_fixtures.sql (teacher A1 11111111, school_owner A2
-- 22222222, teacher B1 33333333, platform admin 44444444) and principal A1
-- from 04_employee_fixtures.sql (77777777).

-- ---------------------------------------------------------------------------
-- 1. A School A member sees School A but not School B.
do $$
declare v_a int; v_b int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_a from public.schools where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  select count(*) into v_b from public.schools where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  execute 'reset role';
  call test_util.record('a school member sees their own school but not another school', v_a = 1 and v_b = 0, 'own=' || v_a || ' other=' || v_b);
end $$;

-- ---------------------------------------------------------------------------
-- 2. A platform admin sees every school.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.schools;
  execute 'reset role';
  call test_util.record('a platform admin sees every school across tenants', v_count >= 2, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. school_owner/principal of School A can update School A's own details.
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.schools set phone = '011-555-0100' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('school_owner can update their own school''s details', v_updated = 1, 'rows updated: ' || v_updated);
end $$;

do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.schools set phone = '011-555-0101' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('principal can update their own school''s details', v_updated = 1, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A teacher (view-only tier) cannot update their own school's details —
-- can_manage_school() is narrower than "any member of the school".
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.schools set phone = '011-555-0199' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('a teacher cannot update their own school''s details', v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant: School B's owner cannot update School A's details, even
-- though they hold the elevated school.manage-equivalent role — just for
-- the wrong tenant.
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  update public.schools set phone = '011-555-0198' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('School B''s owner cannot update School A''s details', v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 6. No DELETE policy exists for `schools` at all — a hard delete is
-- impossible for any authenticated role, including its own owner or a
-- platform admin. INSERT, however, is platform-admin-only (test 7 below):
-- tenant-scoped roles already belong to an existing school by definition,
-- so onboarding a *new* one is a platform-level action.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.schools (name, status) values ('Rogue School', 'active');
    call test_util.record('an authenticated school_owner cannot INSERT a new school (platform admin only)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an authenticated school_owner cannot INSERT a new school (platform admin only)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.schools where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a school is impossible even for its own owner', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;

-- ---------------------------------------------------------------------------
-- 7. A platform admin CAN insert a new school — this is the onboarding path
-- (there is no service_role/manual-SQL step anymore): the new row is
-- created tenant_id-less (schools has no tenant_id column; it *is* the
-- tenant root) and immediately visible back to the same platform admin
-- under policy #2 above.
do $$
declare v_new_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  insert into public.schools (name, status) values ('New Pilot School', 'pending') returning id into v_new_id;
  select count(*) into v_count from public.schools where id = v_new_id;
  execute 'reset role';
  call test_util.record('a platform admin CAN insert a new school', v_count = 1, 'rows visible after insert: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. A platform admin cannot hard-delete the school they just created either
-- — INSERT is the only new capability; DELETE stays closed to everyone.
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  delete from public.schools where name = 'New Pilot School';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('a platform admin cannot hard-delete a school either', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
