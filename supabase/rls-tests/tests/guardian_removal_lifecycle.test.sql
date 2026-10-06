-- Regression suite for the guardian/emergency-contact removal lifecycle
-- (20260816090000_guardian_emergency_contact_lifecycle.sql): archiving a
-- learner_guardians link must both (a) be restricted to authorized,
-- tenant-scoped managers and (b) immediately revoke that guardian's
-- is_learner_guardian()-derived read access, not just hide the row from
-- the guardian's own UI.
--
-- Uses the existing fixtures from 05_learner_fixtures.sql /
-- 07_guardian_emergency_contact_fixtures.sql: guardian/parent 55555555 is
-- linked (learner_guardians 1e110000...0001, is_primary) to Learner A
-- (11110000...0001, School A), which has emergency contact
-- ec110000...0001. Deliberately does NOT touch learner_medical_information
-- for this learner — learner_management.test.sql inserts the one-and-only
-- row for it later (unique index on learner_id) and runs after this file
-- alphabetically; touching it here would break that test's own assertions.

-- ---------------------------------------------------------------------------
-- 1. Baseline: guardian can currently see their linked learner.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('baseline: guardian can see linked learner before archive', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Unauthorized: a plain teacher (no learner.manage) cannot archive the
-- guardian link — RLS's USING clause hides the row, so the UPDATE affects
-- zero rows rather than raising.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.learner_guardians set active = false where id = '1e110000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.learner_guardians where id = '1e110000-0000-0000-0000-000000000001';
  call test_util.record('unauthorized user cannot archive a guardian link',
    v_updated = 0 and v_active = true, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Tenant isolation: School B's owner cannot archive School A's guardian
-- link.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  update public.learner_guardians set active = false where id = '1e110000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.learner_guardians where id = '1e110000-0000-0000-0000-000000000001';
  call test_util.record('cross-tenant manager cannot archive another school''s guardian link',
    v_updated = 0 and v_active = true, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. THE FIX: School A's owner (can_manage_learners) can archive the link.
do $$
declare
  v_updated int;
  v_active boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.learner_guardians set active = false where id = '1e110000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select active into v_active from public.learner_guardians where id = '1e110000-0000-0000-0000-000000000001';
  call test_util.record('authorized manager can archive a guardian link',
    v_updated = 1 and v_active = false, format('rows updated=%s active=%s', v_updated, v_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. THE SECURITY PROPERTY: once archived, the guardian immediately loses
-- read access to the learner via is_learner_guardian() — not just hidden
-- in their own UI, actually revoked at the RLS layer.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('archived guardian immediately loses access to the learner', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Same for emergency-contact access (learner_emergency_contacts_select
-- also calls is_learner_guardian()).
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_emergency_contacts where learner_id = '11110000-0000-0000-0000-000000000001';
  call test_util.record('archived guardian immediately loses access to emergency contacts', v_count = 0, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Regression: staff (can_view_learners) still sees the archived link
-- itself — necessary so the UI can offer a "Restore" action.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_guardians where id = '1e110000-0000-0000-0000-000000000001';
  call test_util.record('staff can still see an archived guardian link (for restore)', v_count = 1, 'rows visible: ' || v_count);

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Reversibility: an authorized manager can restore the link, and access
-- returns immediately — proves the operation is a true archive, not a
-- one-way removal.
do $$
declare
  v_updated int;
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.learner_guardians set active = true where id = '1e110000-0000-0000-0000-000000000001';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learners where id = '11110000-0000-0000-0000-000000000001';

  execute 'reset role';

  call test_util.record('restoring an archived guardian link immediately restores access',
    v_updated = 1 and v_count = 1, format('rows updated=%s learner rows visible after restore=%s', v_updated, v_count));
end;
$$;
