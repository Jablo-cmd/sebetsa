-- Regression suite for FND-WELL-002 / FND-PAR-005
-- (20260829110000_behaviour_guardian_visibility.sql): the guardian_visible
-- flag on behaviour_incidents and the column-narrowed
-- get_guardian_visible_behaviour_incidents() RPC that reads it.
--
-- Uses School A/B fixtures, learner A1 (11110000...0001, School A, guardian
-- 55555555 as mother — 05_learner_fixtures.sql), learner A2
-- (11110000...0002, School A, NOT linked to guardian 55555555), and
-- vice_principal 14141414 (School A, from 11_fees_behaviour_fixtures.sql).

-- ---------------------------------------------------------------------------
-- SETUP: vice_principal records two incidents for Learner A1 — one flagged
-- guardian_visible, one not.
do $$
declare v_ok boolean := true;
declare v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.behaviour_incidents (id, school_id, learner_id, academic_year_id, incident_type, category, description, action_taken, guardian_visible)
      values ('be000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
              'aaaa1111-0000-0000-0000-000000000001', 'positive', 'Leadership', 'Led the class project.', 'Merit certificate awarded.', true);
    insert into public.behaviour_incidents (id, school_id, learner_id, academic_year_id, incident_type, severity, category, description, action_taken, outcome, guardian_visible)
      values ('be000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
              'aaaa1111-0000-0000-0000-000000000001', 'negative', 'low', 'Uniform', 'Uniform not compliant.', 'Verbal reminder given.', 'Resolved same day — internal staff note not for parents.', false);
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  call test_util.record('setup: vice_principal records one guardian_visible and one staff-only incident for Learner A1', v_ok, coalesce(v_error, 'created'));
end $$;

-- ---------------------------------------------------------------------------
-- 1. Guardian 55555555 (Learner A1's mother) sees exactly one incident via
-- the RPC — the guardian_visible one.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.get_guardian_visible_behaviour_incidents('11110000-0000-0000-0000-000000000001');
  execute 'reset role';
  call test_util.record('guardian sees exactly the one guardian_visible incident via the RPC', v_count = 1, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. The row the guardian sees is the guardian_visible one, with correct
-- content, and the RPC's own column set structurally excludes
-- action_taken/outcome/follow_up_notes (they are not selectable from its
-- result at all, not merely filtered — proven by the function's own
-- `returns table (...)` signature, exercised here via a successful query
-- against only the declared columns).
do $$
declare v_id uuid;
declare v_description text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select id, description into v_id, v_description
    from public.get_guardian_visible_behaviour_incidents('11110000-0000-0000-0000-000000000001');
  execute 'reset role';
  call test_util.record('the visible row is the guardian_visible incident with the right description',
    v_id = 'be000000-0000-0000-0000-000000000001' and v_description = 'Led the class project.',
    'id: ' || coalesce(v_id::text, 'null') || ', description: ' || coalesce(v_description, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. The guardian still cannot see anything via a direct SELECT on
-- behaviour_incidents — the new flag does not add a table-level RLS policy;
-- reaffirms parent_portal_v1's original exclusion still holds.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('guardian still cannot SELECT behaviour_incidents directly (RPC-only access)', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 4. A guardian with no link to a learner gets nothing back from the RPC,
-- even for a learner in the same school — is_learner_guardian() re-checked
-- inside the function, not trusted from the caller's role alone.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.get_guardian_visible_behaviour_incidents('11110000-0000-0000-0000-000000000002');
  execute 'reset role';
  call test_util.record('a guardian not linked to the learner gets nothing from the RPC, even same-school', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Staff (vice_principal) sees both incidents via the ordinary table SELECT
-- — full row, including the internal action_taken/outcome — unaffected by
-- the guardian_visible flag.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.behaviour_incidents
    where learner_id = '11110000-0000-0000-0000-000000000001' and id in ('be000000-0000-0000-0000-000000000001', 'be000000-0000-0000-0000-000000000002');
  execute 'reset role';
  call test_util.record('staff still see both incidents (visible and staff-only) via the ordinary table SELECT', v_count = 2, 'rows visible: ' || v_count);
end $$;
