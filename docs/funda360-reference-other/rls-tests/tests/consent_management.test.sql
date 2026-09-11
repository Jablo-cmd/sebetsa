-- Regression suite for FND-SEC-009 (20260829270000_consent_management.sql).
--
-- Reuses existing shared fixtures — nothing here accumulates unbounded
-- state against a shared budget/count (unlike rate_limiting.test.sql's own
-- documented lesson), so no dedicated disposable actors are needed:
-- Learner A1 (11110000...0001, School A) is linked to guardian/parent
-- 55555555; School A also has teacher 11111111 (no learner access at all),
-- school_owner 22222222 (can manage), medical_officer 20202020...
-- (can view, cannot manage). School B's own school_owner 66666666 and
-- Learner B1 (22220000...0001) are used for cross-tenant checks.

-- ---------------------------------------------------------------------------
-- 1. A guardian can record consent for their own linked learner
-- (self-service capture).
do $$
declare v_error text;
declare v_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.consent_records (school_id, learner_id, guardian_profile_id, category, granted)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            '55555555-5555-5555-5555-555555555555', 'photo_media_use', true)
    returning id into v_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  call test_util.record('a guardian can record consent for their own linked learner', v_id is not null, coalesce(v_error, 'id=' || v_id::text));
end $$;

-- ---------------------------------------------------------------------------
-- 2. granted_at was server-derived (not null) and revoked_at is null, on
-- an initial granted=true insert.
do $$
declare v_granted_at timestamptz;
declare v_revoked_at timestamptz;
begin
  select granted_at, revoked_at into v_granted_at, v_revoked_at
    from public.consent_records
    where learner_id = '11110000-0000-0000-0000-000000000001' and category = 'photo_media_use';
  call test_util.record('granted_at is server-derived on a granted=true insert', v_granted_at is not null and v_revoked_at is null, 'granted_at=' || coalesce(v_granted_at::text, 'null') || ' revoked_at=' || coalesce(v_revoked_at::text, 'null'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. A guardian cannot record consent for a learner they are not linked
-- to (Learner B1, School B) — rejected before even reaching the
-- tenant/link-validation trigger, by the INSERT policy itself.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.consent_records (school_id, learner_id, guardian_profile_id, category, granted)
    values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22220000-0000-0000-0000-000000000001',
            '55555555-5555-5555-5555-555555555555', 'photo_media_use', true);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a guardian cannot record consent for a learner they are not linked to', v_ok, coalesce(v_error, 'insert succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. A staff member who can only view learners (medical_officer) cannot
-- record consent.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('20202020-2020-2020-2020-202020202020', 'medical_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.consent_records (school_id, learner_id, guardian_profile_id, category, granted)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            '55555555-5555-5555-5555-555555555555', 'marketing_communications', true);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a view-only staff member (medical_officer) cannot record consent', v_ok, coalesce(v_error, 'insert succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. A staff member who can manage learners (school_owner) can record
-- consent on a guardian's behalf (e.g. a paper form captured in person).
do $$
declare v_error text;
declare v_id uuid;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.consent_records (school_id, learner_id, guardian_profile_id, category, granted)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            '55555555-5555-5555-5555-555555555555', 'marketing_communications', true)
    returning id into v_id;
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';
  call test_util.record('a staff member who can manage learners can record consent on a guardian''s behalf', v_id is not null, coalesce(v_error, 'id=' || v_id::text));
end $$;

-- ---------------------------------------------------------------------------
-- 6. Attaching a guardian_profile_id that is not actually a guardian of
-- the learner is rejected by the link-validation trigger, even for staff
-- who can otherwise manage the learner.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.consent_records (school_id, learner_id, guardian_profile_id, category, granted)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            '11111111-1111-1111-1111-111111111111', 'photo_media_use', true);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like 'insufficient_privilege: guardian_profile_id%';
  end;
  execute 'reset role';
  call test_util.record('a guardian_profile_id that is not an active guardian of the learner is rejected', v_ok, coalesce(v_error, 'insert succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 7. The guardian can view their own recorded consent.
do $$
declare v_count integer;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a guardian can view their own recorded consent', v_count = 2, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. A teacher with no learner access at all cannot see any consent
-- records.
do $$
declare v_count integer;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a teacher with no learner-view access sees zero consent records', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 9. Cross-tenant: School B's own school_owner cannot see School A's
-- consent records.
do $$
declare v_count integer;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('cross-tenant consent records remain invisible', v_count = 0, 'rows visible: ' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 10. A guardian can withdraw (revoke) their own consent — granted flips
-- to false and revoked_at is server-derived, granted_at is untouched
-- (preserves "when it was last actually granted").
do $$
declare v_error text;
declare v_ok boolean := true;
declare v_granted boolean;
declare v_granted_at_before timestamptz;
declare v_granted_at_after timestamptz;
declare v_revoked_at timestamptz;
begin
  select granted_at into v_granted_at_before from public.consent_records
    where learner_id = '11110000-0000-0000-0000-000000000001' and category = 'photo_media_use';

  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    update public.consent_records set granted = false
      where learner_id = '11110000-0000-0000-0000-000000000001' and category = 'photo_media_use';
  exception when others then
    v_ok := false;
    get stacked diagnostics v_error = message_text;
  end;
  execute 'reset role';

  select granted, granted_at, revoked_at into v_granted, v_granted_at_after, v_revoked_at
    from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001' and category = 'photo_media_use';

  call test_util.record('a guardian can withdraw their own consent, with revoked_at server-derived and granted_at preserved',
    v_ok and v_granted = false and v_revoked_at is not null and v_granted_at_after = v_granted_at_before,
    coalesce(v_error, 'granted=' || v_granted::text || ' granted_at unchanged=' || (v_granted_at_after = v_granted_at_before)::text || ' revoked_at=' || coalesce(v_revoked_at::text, 'null')));
end $$;

-- ---------------------------------------------------------------------------
-- 11. Every insert and every granted transition is written to audit_log.
do $$
declare v_created_count integer;
declare v_changed_count integer;
begin
  select count(*) into v_created_count from public.audit_log
    where entity_table = 'consent_records' and action = 'consent_recorded'
      and entity_id in (select id from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001');
  select count(*) into v_changed_count from public.audit_log
    where entity_table = 'consent_records' and action = 'consent_changed'
      and entity_id in (select id from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001');
  call test_util.record('every consent insert and grant/revoke transition is written to audit_log', v_created_count = 2 and v_changed_count = 1, 'created=' || v_created_count || ' changed=' || v_changed_count);
end $$;

-- ---------------------------------------------------------------------------
-- 12. A duplicate (learner, guardian, category) insert is rejected by the
-- unique index — callers must UPDATE the existing row instead.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.consent_records (school_id, learner_id, guardian_profile_id, category, granted)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001',
            '55555555-5555-5555-5555-555555555555', 'photo_media_use', true);
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := v_error like '%consent_records_learner_guardian_category_key%';
  end;
  execute 'reset role';
  call test_util.record('a duplicate (learner, guardian, category) insert is rejected by the unique constraint', v_ok, coalesce(v_error, 'insert succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 13. Hard delete is impossible even for a manager (no DELETE policy,
-- FORCE ROW LEVEL SECURITY).
do $$
declare v_deleted integer;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  delete from public.consent_records where learner_id = '11110000-0000-0000-0000-000000000001';
  get diagnostics v_deleted = row_count;
  execute 'reset role';
  call test_util.record('hard delete of a consent record is impossible even for a manager', v_deleted = 0, 'rows deleted: ' || v_deleted);
end $$;
