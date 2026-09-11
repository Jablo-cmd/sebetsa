-- Regression suite for 20260904090000_grading_scales.sql.
-- Fixtures: School A aaaaaaaa (02_fixtures), school_owner A2 22222222,
-- principal A1 77777777 (04_employee_fixtures), teacher A1 11111111,
-- School B bbbbbbbb + teacher B1 33333333.

-- ---------------------------------------------------------------------------
-- 1. school_owner (academic.manage) can create a scale + non-overlapping bands.
do $$
declare v_scale_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.grading_scales (id, school_id, name, is_default)
  values ('c5a1e000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'CAPS 7-point', true)
  returning id into v_scale_id;
  call test_util.record('school_owner can create a grading scale', v_scale_id is not null, '');

  insert into public.grading_scale_bands (grading_scale_id, school_id, code, label, min_percentage, max_percentage) values
    ('c5a1e000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '7', 'Outstanding', 80, 100),
    ('c5a1e000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '5', 'Substantial', 60, 79),
    ('c5a1e000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '3', 'Moderate', 0, 59);
  call test_util.record('non-overlapping bands insert cleanly', true, '');

  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 2. An overlapping band is rejected by the validate trigger.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.grading_scale_bands (grading_scale_id, school_id, code, label, min_percentage, max_percentage)
    values ('c5a1e000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '6', 'Meritorious', 70, 85);
    call test_util.record('an overlapping band is rejected', false, 'insert succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('an overlapping band is rejected', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 3. resolve_achievement() maps a percentage to the right band, and returns
-- no row when nothing matches / percentage is null.
do $$
declare v_code text; v_rows int;
begin
  select code into v_code from public.resolve_achievement('c5a1e000-0000-0000-0000-000000000001', 84.6);
  call test_util.record('resolve_achievement(84.6) -> band 7', v_code = '7', 'got: ' || coalesce(v_code, 'null'));

  select code into v_code from public.resolve_achievement('c5a1e000-0000-0000-0000-000000000001', 60);
  call test_util.record('resolve_achievement(60) -> band 5 (inclusive lower bound)', v_code = '5', 'got: ' || coalesce(v_code, 'null'));

  select count(*) into v_rows from public.resolve_achievement('c5a1e000-0000-0000-0000-000000000001', null);
  call test_util.record('resolve_achievement(null) returns no row', v_rows = 0, 'rows: ' || v_rows);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A teacher (academic.view but not academic.manage) can read scales but
-- not create them.
do $$
declare v_seen int; v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_seen from public.grading_scales where id = 'c5a1e000-0000-0000-0000-000000000001';
  call test_util.record('a teacher can read a grading scale', v_seen = 1, 'rows: ' || v_seen);

  begin
    insert into public.grading_scales (school_id, name) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Teacher scale');
    call test_util.record('a teacher cannot create a grading scale', false, 'insert succeeded');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot create a grading scale', true, v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant: School B's teacher cannot see School A's scale.
do $$
declare v_seen int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.grading_scales where id = 'c5a1e000-0000-0000-0000-000000000001';
  call test_util.record('School B cannot see School A''s grading scale', v_seen = 0, 'rows: ' || v_seen);
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. A guardian cannot see grading scales at all.
do $$
declare v_seen int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.grading_scales;
  call test_util.record('a guardian sees no grading scales', v_seen = 0, 'rows: ' || v_seen);
  execute 'reset role';
end $$;
