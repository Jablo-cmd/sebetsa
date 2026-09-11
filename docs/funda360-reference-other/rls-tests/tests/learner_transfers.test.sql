-- Regression suite for FND-SIS-007 (20260829180000_learner_transfers.sql):
-- the learner_transfers record-keeping table and its RLS/tenant-consistency
-- guards. Reuses School A/B and learner A1 (11110000...0001, active,
-- 05_learner_fixtures.sql) — learner_transfers carries no exact-count
-- assertion anywhere else in this suite, so no dedicated isolation fixture
-- is needed here (same reasoning as learner_documents_versioning.test.sql).

-- ---------------------------------------------------------------------------
-- 1. A manager (school_owner) can record an outgoing transfer for learner A1.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.learner_transfers (id, school_id, learner_id, direction, other_school_name, other_school_contact, transfer_date, reason) values
    ('7f000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'outgoing', 'Riverside Prep', 'admissions@riverside.example', '2026-09-01', 'Family relocating');

  execute 'reset role';

  select count(*) into v_count from public.learner_transfers where id = '7f000000-0000-0000-0000-000000000001';
  call test_util.record('school_owner can record an outgoing transfer', v_count = 1, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 2. An incoming transfer (a new admission's prior-school history) is
-- equally recordable, independent of the outgoing one above.
do $$
declare v_direction public.learner_transfer_direction;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.learner_transfers (id, school_id, learner_id, direction, other_school_name, transfer_date) values
    ('7f000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'incoming', 'Prior Primary School', '2024-01-10');

  execute 'reset role';

  select direction into v_direction from public.learner_transfers where id = '7f000000-0000-0000-0000-000000000002';
  call test_util.record('an incoming transfer record is independently recordable', v_direction = 'incoming', 'direction=' || v_direction);
end $$;

-- ---------------------------------------------------------------------------
-- 3. learner.view without learner.manage (medical_officer — can_view_learners
-- includes it, can_manage_learners does not, per 20260803190000_learner_
-- management.sql) can see both records but cannot insert one of their own.
do $$
declare v_count int;
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('20202020-2020-2020-2020-202020202020', 'medical_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.learner_transfers where learner_id = '11110000-0000-0000-0000-000000000001';

  begin
    insert into public.learner_transfers (school_id, learner_id, direction, other_school_name, transfer_date) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'outgoing', 'Should not be allowed', '2026-09-01');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;

  execute 'reset role';

  call test_util.record('learner.view can see both transfer records for learner A1', v_count = 2, 'count=' || v_count);
  call test_util.record('learner.view without learner.manage cannot insert a transfer record', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. Tenant isolation: School B cannot see School A's transfer records.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.learner_transfers where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('School B cannot see School A''s transfer records', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. The tenant-consistency trigger rejects a school_id that doesn't match
-- the referenced learner's own school.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.learner_transfers (school_id, learner_id, direction, other_school_name, transfer_date) values
      ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11110000-0000-0000-0000-000000000001', 'outgoing', 'Mismatched school_id', '2026-09-01');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a school_id mismatched with the learner''s own school is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 6. No UPDATE policy — FORCE ROW LEVEL SECURITY makes even the manager's
-- own attempt to edit a transfer record a no-op affecting zero rows (not
-- an outright error, since there's simply no matching-and-updatable row
-- from the caller's perspective — the standard RLS "phantom row" behavior).
do $$
declare v_reason text;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.learner_transfers set reason = 'edited' where id = '7f000000-0000-0000-0000-000000000001';
  execute 'reset role';
  select reason into v_reason from public.learner_transfers where id = '7f000000-0000-0000-0000-000000000001';
  call test_util.record('a transfer record cannot be edited after creation (no UPDATE policy)', v_reason = 'Family relocating', 'reason=' || coalesce(v_reason, '(null)'));
end $$;
