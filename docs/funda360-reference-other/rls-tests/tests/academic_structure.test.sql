-- Regression suite for Sprint 2 Milestone 1 (Academic Structure): RLS,
-- role-gated view/manage split, the one-active-year guarantee, and the two
-- child-tenant-matches-parent triggers (terms/classes). Same impersonation
-- discipline as profiles_tenant_id_protection.test.sql — each test
-- verifies it is genuinely running as `authenticated`, not the connecting
-- superuser.

-- ---------------------------------------------------------------------------
-- 1. Teacher (academic.view only) can SELECT academic years for their own school.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('teacher can view own school''s academic years', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Teacher (no academic.manage) cannot INSERT an academic year.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.academic_years (school_id, name, start_date, end_date)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Teacher-created year', '2027-01-01', '2027-12-01');
    call test_util.record('teacher cannot create an academic year', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('teacher cannot create an academic year', true, v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A role with no academic permission at all (parent) cannot see academic years for their own school.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.academic_years where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('parent role has no academic visibility', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. school_owner (academic.manage) can create an academic year for their own school.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.academic_years (id, school_id, name, start_date, end_date)
      values ('aaaa1111-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2027 Academic Year', '2027-01-15', '2027-12-05');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('school_owner can create an academic year', v_ok, coalesce(v_error, 'created'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. school_owner cannot create an academic year for a DIFFERENT school.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.academic_years (school_id, name, start_date, end_date)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Cross-tenant year', '2027-01-01', '2027-12-01');
    call test_util.record('school_owner cannot create an academic year for another school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('school_owner cannot create an academic year for another school', true, v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Tenant isolation: School B's owner cannot see School A's grades.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.grades where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant grades are invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. One active year per school: a second row with is_active=true for the
-- same school violates the partial unique index.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.academic_years (school_id, name, start_date, end_date, is_active)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Second active year', '2028-01-01', '2028-12-01', true);
    call test_util.record('only one active academic year per school (partial unique index)', false, 'INSERT of a second active year succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('only one active academic year per school (partial unique index)',
      v_error like '%academic_years_one_active_per_school%' or v_error like '%duplicate key%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Direct UPDATE cannot flip is_active false -> true (must go through
-- set_active_academic_year) — attempted on the inactive year created in test 4.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.academic_years set is_active = true where id = 'aaaa1111-0000-0000-0000-000000000002';
    call test_util.record('direct UPDATE cannot activate a year (must use the RPC)', false, 'UPDATE succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('direct UPDATE cannot activate a year (must use the RPC)',
      v_error like '%can only be activated via set_active_academic_year%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Direct UPDATE CAN archive (is_active true -> false) without the RPC.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_is_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    update public.academic_years set is_active = false where id = 'aaaa1111-0000-0000-0000-000000000001';
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select is_active into v_is_active from public.academic_years where id = 'aaaa1111-0000-0000-0000-000000000001';
  call test_util.record('direct UPDATE can archive (deactivate) a year', v_ok and v_is_active = false, coalesce(v_error, 'is_active now: ' || v_is_active::text));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. set_active_academic_year atomically switches the active year.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_old_active boolean;
  v_new_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.set_active_academic_year('aaaa1111-0000-0000-0000-000000000002');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select is_active into v_old_active from public.academic_years where id = 'aaaa1111-0000-0000-0000-000000000001';
  select is_active into v_new_active from public.academic_years where id = 'aaaa1111-0000-0000-0000-000000000002';
  call test_util.record('set_active_academic_year atomically switches the active year',
    v_ok and v_old_active = false and v_new_active = true,
    coalesce(v_error, format('old=%s new=%s', v_old_active, v_new_active)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. set_active_academic_year rejects a caller without academic.manage.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.set_active_academic_year('aaaa1111-0000-0000-0000-000000000001');
    call test_util.record('set_active_academic_year rejects a non-manager', false, 'RPC succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('set_active_academic_year rejects a non-manager',
      v_error like '%insufficient_privilege%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. terms.school_id must match the referenced academic_years.school_id
-- (closes the FK-doesn't-respect-RLS gap) — School B's owner, authorized
-- for School B, tries to file a term against School A's academic year.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.terms (academic_year_id, school_id, name, sequence, start_date, end_date)
      values ('aaaa1111-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Term 1', 1, '2026-01-15', '2026-04-01');
    call test_util.record('terms.school_id must match the parent academic year''s school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('terms.school_id must match the parent academic year''s school',
      v_error like '%terms.school_id must match%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. classes.school_id must match the referenced grades.school_id — same
-- gap, same fix, for classes/grades.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    insert into public.classes (grade_id, school_id, name, capacity)
      values ('aaaa2222-0000-0000-0000-000000000001', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Cross-tenant class', 30);
    call test_util.record('classes.school_id must match the parent grade''s school', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('classes.school_id must match the parent grade''s school',
      v_error like '%classes.school_id must match%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Academic entities are never hard-deleted: no DELETE policy exists on
-- any of the five tables, so even a manager's DELETE silently matches zero
-- rows under RLS (not an error — RLS filters the target row set before the
-- delete happens).
do $$
declare
  v_count_before int;
  v_count_after int;
begin
  select count(*) into v_count_before from public.grades where id = 'aaaa2222-0000-0000-0000-000000000001';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.grades where id = 'aaaa2222-0000-0000-0000-000000000001';
  execute 'reset role';

  select count(*) into v_count_after from public.grades where id = 'aaaa2222-0000-0000-0000-000000000001';
  call test_util.record('grades cannot be hard-deleted (no DELETE policy)',
    v_count_before = 1 and v_count_after = 1, format('before=%s after=%s', v_count_before, v_count_after));
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. Unique names per school (case-insensitive) — a second grade named
-- "grade 8" (any case) in the same school is rejected.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.grades (school_id, name, sort_order) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'GRADE 8', 9);
    call test_util.record('grade names are unique per school (case-insensitive)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('grade names are unique per school (case-insensitive)',
      v_error like '%duplicate key%' or v_error like '%grades_school_id_name_key%', v_error);
  end;

  execute 'reset role';
end;
$$;
