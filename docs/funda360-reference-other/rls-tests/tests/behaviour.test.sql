-- Regression suite for the Behaviour domain (behaviour_incidents). Uses
-- School A/B, learner 11110000...0001 (School A) / 22220000...0001 (School
-- B), academic year aaaa1111...0001 (School A) / bbbb1111...0001 (School B)
-- from earlier fixtures, and vice_principal 14141414 / department_head
-- 15151515 / principal 77777777 / teacher 11111111 (all School A) from
-- 11_fees_behaviour_fixtures.sql.

-- ---------------------------------------------------------------------------
-- 1. vice_principal can insert a negative incident for a learner in their
-- own school — exercises behaviour_incidents_validate_tenant()'s SECURITY
-- DEFINER read of `learners`.
do $$
declare v_incident_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, severity, description)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'negative', 'medium', 'Disruption in class')
    returning id into v_incident_id;
  select count(*) into v_count from public.behaviour_incidents where id = v_incident_id;
  execute 'reset role';
  call test_util.record('vice_principal can insert and see a behaviour incident for their own school', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. department_head can also insert (same permission tier) — a positive
-- commendation this time.
do $$
declare v_incident_id uuid;
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('15151515-1515-1515-1515-151515151515', 'department_head', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, description)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'positive', 'Helped a classmate')
    returning id into v_incident_id;
  select count(*) into v_count from public.behaviour_incidents where id = v_incident_id;
  execute 'reset role';
  call test_util.record('department_head can insert and see a behaviour incident for their own school', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. principal (school-wide oversight) can view and manage.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('principal can view behaviour incidents', v_count >= 2, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A teacher (no behaviour permission) cannot view or insert.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a teacher cannot view any behaviour incidents', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, description)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'negative', 'Rogue incident');
    call test_util.record('a teacher cannot insert a behaviour incident', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('a teacher cannot insert a behaviour incident', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Cross-tenant: School B's owner cannot see or record incidents for
-- School A's learner.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('School B''s owner cannot see School A''s behaviour incidents', v_count = 0, 'rows visible: ' || v_count);
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  begin
    insert into public.behaviour_incidents (school_id, learner_id, academic_year_id, incident_type, description)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11110000-0000-0000-0000-000000000001', 'bbbb1111-0000-0000-0000-000000000001', 'negative', 'Cross-tenant incident');
    call test_util.record('School B''s owner cannot record an incident against School A''s learner (cross-tenant FK check)', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('School B''s owner cannot record an incident against School A''s learner (cross-tenant FK check)', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 6. A platform admin sees behaviour incidents across tenants.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('44444444-4444-4444-4444-444444444444', 'platform_administrator', null), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents;
  execute 'reset role';
  call test_util.record('a platform admin sees behaviour incidents across tenants', v_count >= 2, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 7. No DELETE policy exists — a mismarked incident is voided (active=false),
-- never hard-deleted, even by the vice_principal who created it.
do $$
declare v_deleted int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.behaviour_incidents where learner_id = '11110000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a behaviour incident is impossible even for the vice_principal who created it', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
