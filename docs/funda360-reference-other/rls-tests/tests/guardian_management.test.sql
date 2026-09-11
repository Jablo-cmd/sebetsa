-- Regression suite for Guardian Management
-- (20260824090000_guardian_management.sql): admin_create_guardian()
-- provisioning + its can_manage_learners() gate, guardian_profile_details
-- RLS + tenant isolation, the new relationship metadata columns, multiple
-- learners per guardian, multiple guardians per learner, relationship
-- updates, and no-hard-delete.
--
-- Uses 05_learner_fixtures.sql (guardian/parent 55555555 linked to Learner
-- A1 11110000...0001 as mother/primary; Learner A2 11110000...0002 exists,
-- unlinked; school_owner 22222222; admissions_officer 10101010; teacher
-- 11111111) and 12_guardian_management_fixtures.sql (guardian 59595959,
-- role=guardian not role=parent, linked to Learner A1 as father/non-primary
-- via 1e110000...0002).
--
-- Deliberately does NOT touch link 1e110000...0001 (archive/restore) —
-- guardian_removal_lifecycle.test.sql runs after this file alphabetically
-- and depends on that link starting active=true. All archive/restore/
-- relationship-metadata tests here use the new 1e110000...0002 link
-- instead, so the two suites never interfere with each other's state.

-- ---------------------------------------------------------------------------
-- 1. admin_create_guardian: admissions_officer (can_manage_learners, but
-- NOT can_assign_role for any staff role, and NOT can_manage_profiles) can
-- create a new guardian.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_id uuid;
  v_role public.user_role;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('10101010-1010-1010-1010-101010101010', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    select user_id into v_id from public.admin_create_guardian(
      'new.guardian.a1@schoola.test', 'New', 'Guardian', '+27831234444', null, '12 Main Road', 'ID998877');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select role into v_role from public.profiles where id = v_id;
  call test_util.record('admissions_officer can create a new guardian via admin_create_guardian',
    v_ok and v_role = 'guardian', coalesce(v_error, 'created role=' || coalesce(v_role::text, 'null')));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The new guardian's address/id_number were written to
-- guardian_profile_details in the same call.
do $$
declare
  v_address text;
  v_id_number text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select gpd.address, gpd.id_number into v_address, v_id_number
    from public.guardian_profile_details gpd
    join public.profiles p on p.id = gpd.guardian_profile_id
    where p.email = 'new.guardian.a1@schoola.test';

  execute 'reset role';

  call test_util.record('admin_create_guardian writes guardian_profile_details atomically',
    v_address = '12 Main Road' and v_id_number = 'ID998877',
    format('address=%s id_number=%s', v_address, v_id_number));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Permission restriction: a teacher (no can_manage_learners) cannot call
-- admin_create_guardian.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.admin_create_guardian('rogue.guardian@schoola.test', 'Rogue', 'Guardian', null);
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('teacher cannot create a guardian via admin_create_guardian',
    v_ok, coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Tenant isolation: School B's owner cannot target School A via
-- p_tenant_id (only platform admins may do that — same rule as
-- admin_create_user).
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    perform public.admin_create_guardian(
      'cross.tenant.guardian@schoolb.test', 'Cross', 'Tenant', null, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  -- Even though the call did not raise (non-platform-admins simply have
  -- p_tenant_id ignored in favour of current_tenant_id(), exactly like
  -- admin_create_user), the guardian must land in School B, never School A.
  call test_util.record('non-platform-admin cannot target another tenant via admin_create_guardian',
    v_ok, coalesce(v_error, 'call raised unexpectedly'));
end;
$$;

do $$
declare
  v_tenant uuid;
begin
  select tenant_id into v_tenant from public.profiles where email = 'cross.tenant.guardian@schoolb.test';
  call test_util.record('cross-tenant admin_create_guardian call lands in the caller''s own tenant, not the requested one',
    v_tenant = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'landed in tenant: ' || coalesce(v_tenant::text, 'null'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Multiple learners per guardian: link the existing guardian 55555555
-- (already linked to Learner A1) to a second, dedicated learner, Learner A3
-- (11110000...0004, added by 12_guardian_management_fixtures.sql — NOT
-- Learner A2, which learner_management.test.sql's own guardian-isolation
-- test depends on staying unlinked from 55555555; see that fixture file's
-- header comment for why).
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.learner_guardians (id, school_id, learner_id, guardian_profile_id, relationship_type, is_primary)
      values ('1e110000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              '11110000-0000-0000-0000-000000000004', '55555555-5555-5555-5555-555555555555', 'mother', true);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('one guardian can be linked to multiple learners', v_ok, coalesce(v_error, 'linked'));
end;
$$;

do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_guardians
    where guardian_profile_id = '55555555-5555-5555-5555-555555555555' and active;

  execute 'reset role';
  call test_util.record('guardian now has two active learner links', v_count = 2, 'links visible: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Multiple guardians per learner: Learner A1 already has mother
-- (55555555) and father (59595959, from fixtures) both active.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_guardians
    where learner_id = '11110000-0000-0000-0000-000000000001' and active;

  execute 'reset role';
  call test_util.record('one learner can have multiple active guardians', v_count = 2, 'guardians visible: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Relationship updates: is_primary / is_emergency_contact /
-- is_authorized_pickup are all independently writable by an authorized
-- manager, on the father link (1e110000...0002).
do $$
declare
  v_updated int;
  v_emergency boolean;
  v_pickup boolean;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.learner_guardians
    set is_emergency_contact = true, is_authorized_pickup = true
    where id = '1e110000-0000-0000-0000-000000000002';
  get diagnostics v_updated = row_count;

  execute 'reset role';

  select is_emergency_contact, is_authorized_pickup into v_emergency, v_pickup
    from public.learner_guardians where id = '1e110000-0000-0000-0000-000000000002';

  call test_util.record('relationship emergency-contact / authorised-pickup flags are independently writable',
    v_updated = 1 and v_emergency and v_pickup, format('updated=%s emergency=%s pickup=%s', v_updated, v_emergency, v_pickup));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Deactivation (archive) on the father link — never hard-deleted,
-- metadata (relationship_type, is_emergency_contact, is_authorized_pickup)
-- survives archiving so it is preserved if later restored.
do $$
declare
  v_updated int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  update public.learner_guardians set active = false where id = '1e110000-0000-0000-0000-000000000002';
  get diagnostics v_updated = row_count;

  execute 'reset role';
  call test_util.record('father guardian link can be deactivated (archived)', v_updated = 1, 'rows updated: ' || v_updated);
end;
$$;

do $$
declare
  v_active boolean;
  v_relationship public.guardian_relationship_type;
  v_emergency boolean;
begin
  select active, relationship_type, is_emergency_contact into v_active, v_relationship, v_emergency
    from public.learner_guardians where id = '1e110000-0000-0000-0000-000000000002';
  call test_util.record('archived relationship retains its historical metadata, not deleted',
    v_active = false and v_relationship = 'father' and v_emergency = true,
    format('active=%s relationship=%s emergency=%s', v_active, v_relationship, v_emergency));
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. guardian_profile_details tenant isolation: School B's owner cannot see
-- School A's guardian_profile_details rows.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.guardian_profile_details where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  execute 'reset role';
  call test_util.record('cross-tenant manager cannot see another school''s guardian_profile_details',
    v_count = 0, 'rows visible: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. guardian_profile_details tenant-match trigger: cannot attach details
-- for a School A guardian under School B's school_id.
do $$
declare
  v_error text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.guardian_profile_details (school_id, guardian_profile_id, address)
      values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '55555555-5555-5555-5555-555555555555', 'nowhere');
    call test_util.record('guardian_profile_details.school_id must match the guardian''s own tenant', false, 'INSERT succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('guardian_profile_details.school_id must match the guardian''s own tenant',
      v_error like '%guardian_profile_id must belong to the same school%', v_error);
  end;

  execute 'reset role';
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Permission restriction: a teacher (no can_view_learners) cannot read
-- guardian_profile_details at all.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.guardian_profile_details where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  execute 'reset role';
  call test_util.record('teacher cannot view guardian_profile_details', v_count = 0, 'rows visible: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. No hard delete: guardian_profile_details has no DELETE policy. Uses
-- the row created by test 1/2 (new.guardian.a1@schoola.test), which is
-- known to exist, so this actually exercises a real DELETE attempt rather
-- than a vacuous zero-rows-either-way comparison.
do $$
declare
  v_guardian_id uuid;
  v_before int;
  v_after int;
begin
  select id into v_guardian_id from public.profiles where email = 'new.guardian.a1@schoola.test';

  select count(*) into v_before from public.guardian_profile_details where guardian_profile_id = v_guardian_id;

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.guardian_profile_details where guardian_profile_id = v_guardian_id;
  execute 'reset role';

  select count(*) into v_after from public.guardian_profile_details where guardian_profile_id = v_guardian_id;

  call test_util.record('guardian_profile_details cannot be hard-deleted (no DELETE policy)',
    v_before = 1 and v_after = 1, format('before=%s after=%s', v_before, v_after));
end;
$$;
