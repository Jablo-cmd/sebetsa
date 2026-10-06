-- Regression suite for Sprint 3 Milestone 3 Phase 0
-- (20260805100000_guardian_emergency_contacts_access.sql): guardian
-- read-only access to learner_emergency_contacts, alongside proof that
-- staff access and tenant isolation are unaffected by the change.

-- ---------------------------------------------------------------------------
-- 1. Guardian (linked via learner_guardians, no learner.view) can see the
-- emergency contact belonging to their own linked learner.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_emergency_contacts
    where learner_id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('guardian can view emergency contacts for their own linked learner', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Same guardian cannot see the emergency contact belonging to a learner
-- they are not linked to.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_emergency_contacts
    where learner_id = '22220000-0000-0000-0000-000000000001';
  call test_util.record('guardian cannot view emergency contacts belonging to another learner', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Tenant isolation: School B's owner cannot see School A's emergency
-- contacts, mirroring the existing "cross-tenant learners are invisible" check.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_emergency_contacts
    where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('cross-tenant emergency contacts remain invisible', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. THE REGRESSION CHECK: staff access (can_view_learners) is unchanged by
-- this migration — School A's owner still sees the full directory's contacts.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_emergency_contacts
    where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  call test_util.record('existing staff access to emergency contacts still works', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;
