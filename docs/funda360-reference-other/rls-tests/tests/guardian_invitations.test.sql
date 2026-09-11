-- Regression suite for Guardian Invitations
-- (20260827090000_guardian_invitations.sql): send_guardian_invitation()'s
-- can_manage_learners() gate, role/status validation, resend-supersedes,
-- the one-pending-per-guardian constraint, revoke_guardian_invitation(),
-- accept_guardian_invitation() (including expiry), get_my_guardian_invitation()'s
-- self-scoping, RLS on the table itself, no-hard-delete, and the
-- anon/unauthenticated rejection paths every privileged function in this
-- schema is expected to have (see function_security_hardening.test.sql).
--
-- Uses 03_academic_fixtures.sql (guardian/parent 55555555, School A, linked
-- to Learner A1 11110000...0001 as mother/primary), 02_fixtures.sql
-- (teacher 11111111, school_owner 22222222, both School A),
-- 05_learner_fixtures.sql (admissions_officer 10101010, School A; guardian
-- 59595959, role=guardian, School A), 13_parent_portal_fixtures.sql
-- (guardian/parent 18181818, School B; school_owner 66666666, School B),
-- and 14_guardian_invitations_fixtures.sql (guardian 9e9e9e9e, School A,
-- with an already-expired pending invitation 9e9e0000...0001).

-- ---------------------------------------------------------------------------
-- 1. school_owner can send an invitation for an existing, own-tenant guardian.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_status public.guardian_invitation_status;
  v_expires timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    select status, expires_at into v_status, v_expires
      from public.send_guardian_invitation('55555555-5555-5555-5555-555555555555');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('school_owner can send a guardian invitation',
    v_ok and v_status = 'pending' and v_expires > now(), coalesce(v_error, format('status=%s expires_at=%s', v_status, v_expires)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. teacher (no can_manage_learners) cannot send an invitation.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.send_guardian_invitation('55555555-5555-5555-5555-555555555555');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('teacher cannot send a guardian invitation',
    v_ok and v_error like '%insufficient_privilege%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Cross-tenant: School B's owner cannot invite School A's guardian.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    perform public.send_guardian_invitation('55555555-5555-5555-5555-555555555555');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('cross-tenant manager cannot invite another school''s guardian',
    v_ok and v_error like '%insufficient_privilege%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Cannot invite a profile that isn't a guardian (role check).
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.send_guardian_invitation('11111111-1111-1111-1111-111111111111');
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('cannot send a guardian invitation to a non-guardian profile',
    v_ok and v_error like '%invalid_role%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Resend supersedes: sending a second invitation to 55555555 (already
-- has a pending one from test 1) revokes the first and creates exactly one
-- new pending row.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_first_id uuid;
  v_second_id uuid;
  v_first_status public.guardian_invitation_status;
  v_pending_count int;
begin
  select id into v_first_id from public.guardian_invitations
    where guardian_profile_id = '55555555-5555-5555-5555-555555555555' and status = 'pending';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    select id into v_second_id from public.send_guardian_invitation('55555555-5555-5555-5555-555555555555');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';

  select status into v_first_status from public.guardian_invitations where id = v_first_id;
  select count(*) into v_pending_count from public.guardian_invitations
    where guardian_profile_id = '55555555-5555-5555-5555-555555555555' and status = 'pending';

  call test_util.record('resending an invitation supersedes the previous pending one',
    v_ok and v_second_id <> v_first_id and v_first_status = 'revoked' and v_pending_count = 1,
    coalesce(v_error, format('first_status=%s pending_count=%s new_id_differs=%s', v_first_status, v_pending_count, v_second_id <> v_first_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The one-pending-per-guardian partial unique index rejects a direct
-- INSERT stacking a second pending row, independent of the RPC's own logic.
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    insert into public.guardian_invitations (school_id, guardian_profile_id, status, expires_at)
      values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', 'pending', now() + interval '3 days');
    v_ok := false;
  exception when unique_violation then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('a second pending invitation for the same guardian is rejected at the constraint level',
    v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Revoke: admissions_officer sends an invitation to guardian 59595959,
-- then revokes it.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_status public.guardian_invitation_status;
  v_revoked_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('10101010-1010-1010-1010-101010101010', 'admissions_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.send_guardian_invitation('59595959-5959-5959-5959-595959595959');
    select status, revoked_at into v_status, v_revoked_at from public.revoke_guardian_invitation(
      (select id from public.guardian_invitations where guardian_profile_id = '59595959-5959-5959-5959-595959595959' and status = 'pending'));
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('admissions_officer can revoke a pending invitation',
    v_ok and v_status = 'revoked' and v_revoked_at is not null, coalesce(v_error, format('status=%s revoked_at=%s', v_status, v_revoked_at)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Revoking a non-pending invitation (already revoked, from test 7) fails.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_id uuid;
begin
  select id into v_id from public.guardian_invitations
    where guardian_profile_id = '59595959-5959-5959-5959-595959595959' and status = 'revoked';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.revoke_guardian_invitation(v_id);
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('an already-revoked invitation cannot be revoked again',
    v_ok and v_error like '%invalid_state%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Full accept flow: School B owner invites guardian 18181818; the
-- guardian accepts their own invitation.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_status public.guardian_invitation_status;
  v_accepted_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  perform public.send_guardian_invitation('18181818-1818-1818-1818-181818181818');
  execute 'reset role';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('18181818-1818-1818-1818-181818181818', 'parent', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    select status, accepted_at into v_status, v_accepted_at from public.accept_guardian_invitation();
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('an invited guardian can accept their own invitation',
    v_ok and v_status = 'accepted' and v_accepted_at is not null, coalesce(v_error, format('status=%s accepted_at=%s', v_status, v_accepted_at)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. The same guardian cannot accept a second time (already_accepted).
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('18181818-1818-1818-1818-181818181818', 'parent', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    perform public.accept_guardian_invitation();
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('an already-accepted invitation cannot be accepted again',
    v_ok and v_error like '%already_accepted%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. An accepted invitation cannot be revoked.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_id uuid;
begin
  select id into v_id from public.guardian_invitations
    where guardian_profile_id = '18181818-1818-1818-1818-181818181818' and status = 'accepted';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  begin
    perform public.revoke_guardian_invitation(v_id);
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('an accepted invitation cannot be revoked',
    v_ok and v_error like '%invalid_state%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. get_my_guardian_invitation is self-scoped: guardian 55555555 (has a
-- pending invitation from test 5, linked only to Learner A1) sees their own
-- invitation and only their own linked child, never another guardian's data.
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    select public.get_my_guardian_invitation() into v_result;
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := false;
  end;

  execute 'reset role';
  call test_util.record('get_my_guardian_invitation returns the caller''s own pending invitation and only their own linked child',
    v_ok
      and v_result -> 'invitation' ->> 'effectiveStatus' = 'pending'
      and jsonb_array_length(v_result -> 'children') = 1
      and v_result -> 'children' -> 0 ->> 'id' = '11110000-0000-0000-0000-000000000001'
      and v_result ->> 'schoolName' = 'School A',
    coalesce(v_error, v_result::text));
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. accept_guardian_invitation rejects an expired invitation (guardian
-- 9e9e9e9e, fixture invitation 9e9e0000...0001 already expired).
do $$
declare
  v_error text;
  v_ok boolean := true;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('9e9e9e9e-9e9e-9e9e-9e9e-9e9e9e9e9e9e', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  begin
    perform public.accept_guardian_invitation();
    v_ok := false;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;

  execute 'reset role';
  call test_util.record('an expired invitation cannot be accepted',
    v_ok and v_error like '%expired%', coalesce(v_error, 'call succeeded unexpectedly'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. get_my_guardian_invitation reports effectiveStatus = 'expired' for
-- that same guardian, even though the stored status column is still
-- 'pending' (see the enum's comment: expiry is derived, not stored).
do $$
declare
  v_error text;
  v_ok boolean := true;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('9e9e9e9e-9e9e-9e9e-9e9e-9e9e9e9e9e9e', 'guardian', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select public.get_my_guardian_invitation() into v_result;

  execute 'reset role';
  call test_util.record('get_my_guardian_invitation derives effectiveStatus=expired from expires_at, not a stored status',
    v_result -> 'invitation' ->> 'status' = 'pending' and v_result -> 'invitation' ->> 'effectiveStatus' = 'expired',
    v_result::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- 15. RLS: a teacher (no can_view_learners) sees zero guardian_invitations
-- rows even within their own tenant.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.guardian_invitations where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  execute 'reset role';
  call test_util.record('teacher cannot view guardian_invitations (no can_view_learners)', v_count = 0, 'rows visible: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. RLS: cross-tenant isolation on SELECT — School B's owner cannot see
-- School A's guardian_invitations rows.
do $$
declare
  v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.guardian_invitations where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  execute 'reset role';
  call test_util.record('cross-tenant manager cannot see another school''s guardian_invitations',
    v_count = 0, 'rows visible: ' || v_count);
end;
$$;

-- ---------------------------------------------------------------------------
-- 17. No hard delete: guardian_invitations has no DELETE policy.
do $$
declare
  v_id uuid;
  v_before int;
  v_after int;
begin
  select id into v_id from public.guardian_invitations
    where guardian_profile_id = '9e9e9e9e-9e9e-9e9e-9e9e-9e9e9e9e9e9e';

  select count(*) into v_before from public.guardian_invitations where id = v_id;

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.guardian_invitations where id = v_id;
  execute 'reset role';

  select count(*) into v_after from public.guardian_invitations where id = v_id;

  call test_util.record('guardian_invitations cannot be hard-deleted (no DELETE policy)',
    v_before = 1 and v_after = 1, format('before=%s after=%s', v_before, v_after));
end;
$$;

-- ---------------------------------------------------------------------------
-- 18. anon cannot execute any of the four new functions directly (the
-- blanket function_security_hardening revoke covers new functions too, via
-- its `alter default privileges ... revoke execute on functions from
-- public`, since anon/authenticated grants are otherwise inherited from
-- PUBLIC — see that migration's closing statement).
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.send_guardian_invitation('55555555-5555-5555-5555-555555555555');
    call test_util.record('anon cannot execute send_guardian_invitation directly', false, 'call succeeded unexpectedly');
  exception when insufficient_privilege then
    get stacked diagnostics v_error = message_text;
    call test_util.record('anon cannot execute send_guardian_invitation directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.get_my_guardian_invitation();
    call test_util.record('anon cannot execute get_my_guardian_invitation directly', false, 'call succeeded unexpectedly');
  exception when insufficient_privilege then
    get stacked diagnostics v_error = message_text;
    call test_util.record('anon cannot execute get_my_guardian_invitation directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.accept_guardian_invitation();
    call test_util.record('anon cannot execute accept_guardian_invitation directly', false, 'call succeeded unexpectedly');
  exception when insufficient_privilege then
    get stacked diagnostics v_error = message_text;
    call test_util.record('anon cannot execute accept_guardian_invitation directly', true, 'correctly rejected: ' || v_error);
  end;
  execute 'reset role';
end $$;

-- ---------------------------------------------------------------------------
-- 19. An authenticated session with no resolvable auth.uid() (no `sub`
-- claim) is rejected by the functions' own internal check, distinct from
-- the anon grant boundary tested above.
do $$
declare v_error text;
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role authenticated';
  begin
    perform public.get_my_guardian_invitation();
    call test_util.record('authenticated session with no sub claim is rejected by get_my_guardian_invitation', false, 'call succeeded unexpectedly');
  exception when others then
    get stacked diagnostics v_error = message_text;
    call test_util.record('authenticated session with no sub claim is rejected by get_my_guardian_invitation',
      v_error like '%unauthenticated%', v_error);
  end;
  execute 'reset role';
end $$;
