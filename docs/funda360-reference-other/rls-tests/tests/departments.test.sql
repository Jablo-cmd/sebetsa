-- Regression suite for the `departments` table — previously covered only
-- indirectly via employee fixtures. View is can_view_employees
-- (owner/principal/hr_manager); manage is can_manage_employees, which is
-- narrower than view — it excludes principal (owner/hr_manager only), the
-- one asymmetry worth pinning down explicitly. Uses departments
-- dddd1111 (School A "Finance") / dddd2222 (School B "Finance") and users
-- from 02_fixtures.sql + 04_employee_fixtures.sql (principal A1 77777777,
-- hr_manager A1 88888888).

-- ---------------------------------------------------------------------------
-- 1. HR manager can view their school's departments.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.departments where id = 'dddd1111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('hr_manager can view their school''s departments', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Principal can also view departments (can_view_employees includes
-- principal)...
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.departments where id = 'dddd1111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('principal can view departments', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. ...but CANNOT create or rename one — can_manage_employees deliberately
-- excludes principal, unlike most other academic/learner manage checks
-- where principal is always included. This is the one real asymmetry in
-- the role model worth a dedicated negative test.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.departments (school_id, name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rogue Department');
    call test_util.record('a principal cannot create a department (view-only, unlike most other domains)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a principal cannot create a department (view-only, unlike most other domains)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. HR manager CAN create a department.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.departments (id, school_id, name) values ('dddd1111-0000-0000-0000-000000000099', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Sports');
  select count(*) into v_count from public.departments where id = 'dddd1111-0000-0000-0000-000000000099';
  execute 'reset role';
  call test_util.record('hr_manager can create a department', v_count = 1, 'rows created: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant: School B's owner cannot see or rename School A's
-- department.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.departments where id = 'dddd1111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('cross-tenant departments remain invisible', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  update public.departments set name = 'Hijacked' where id = 'dddd1111-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('School B''s owner cannot rename School A''s department', v_updated = 0, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 6. A teacher (no employee.view at all) cannot see any department.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.departments where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('a teacher without employee.view cannot see any department', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 7. No DELETE policy — hard delete is impossible even for hr_manager.
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.departments where id = 'dddd1111-0000-0000-0000-000000000099';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a department is impossible even for hr_manager', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
