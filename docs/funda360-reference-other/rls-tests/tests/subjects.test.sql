-- Regression suite for the `subjects` table — previously covered only
-- indirectly through teaching-assignment/assessment fixtures. Same
-- view/manage split as academic_years/terms/grades/classes
-- (can_view_academic / can_manage_academic). Uses School A/B and users
-- from 02_fixtures.sql; creates its own subject rows (cafe-prefixed, named
-- "Physical Sciences" — deliberately NOT "Mathematics", which
-- 08_teaching_assignment_fixtures.sql already seeds for both schools under
-- the subjects_school_id_name_key unique index).

insert into public.subjects (id, school_id, name, code, active) values
  ('cafe1111-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Physical Sciences', 'PSCI', true),
  ('cafe2222-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Physical Sciences', 'PSCI', true);

-- ---------------------------------------------------------------------------
-- 1. School-wide view: a teacher (view-tier) can see their school's subject
-- catalogue even though they cannot manage it.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.subjects where id = 'cafe1111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a teacher can view their school''s subject catalogue', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Cross-tenant isolation: School B's teacher cannot see School A's
-- subject.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.subjects where id = 'cafe1111-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('cross-tenant subjects remain invisible', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. A teacher (view-tier) cannot create or archive a subject —
-- can_manage_academic() is required, not just can_view_academic().
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.subjects (school_id, name, code) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Rogue Subject', 'ROG');
    call test_util.record('a teacher cannot create a subject', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot create a subject', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Cross-tenant write: School B's owner cannot create a subject scoped to
-- School A.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.subjects (school_id, name, code) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Cross Tenant Subject', 'XT');
    call test_util.record('School B''s owner cannot create a subject scoped to School A', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s owner cannot create a subject scoped to School A', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Authorized manager (school_owner) can archive a subject — the
-- active=false pattern every academic table uses instead of hard delete.
do $$
declare v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.subjects set active = false where id = 'cafe1111-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;
  execute 'reset role';
  call test_util.record('school_owner can archive a subject', v_updated = 1, 'rows updated: ' || v_updated);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Duplicate name within the same school is rejected (subjects_school_id
-- _name_key), proving the unique constraint that backs the app's "no
-- duplicate subject name" validation actually exists at the DB layer.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.subjects (school_id, name, code) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'mathematics', 'MATH2');
    call test_util.record('duplicate subject name (case-insensitive) within a school is rejected', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('duplicate subject name (case-insensitive) within a school is rejected',
      v_error like '%duplicate key%', 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 7. No DELETE policy — hard delete is impossible even for an authorized
-- manager.
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.subjects where id = 'cafe1111-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a subject is impossible even for an authorized manager', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
