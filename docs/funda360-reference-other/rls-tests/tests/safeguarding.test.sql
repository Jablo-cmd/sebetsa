-- Regression suite for FND-WELL-003 (20260829240000_safeguarding.sql):
-- safeguarding_concerns' deliberately narrow RLS (school_owner/principal
-- ONLY — narrower than behaviour or medical), the resolved_at sync
-- trigger, and the audit_log trail on create/status-change.
--
-- Uses School A/B, learner A1 (11110000...0001, School A), school_owner
-- 22222222, principal 77777777, vice_principal/medical_officer are NOT
-- pre-seeded in the base fixtures for School A with those exact roles, so
-- this suite synthesizes their JWTs directly against existing profile ids
-- where safe (RLS role checks read the JWT claim, not the profiles table,
-- so this is a legitimate way to test "a role that isn't school_owner/
-- principal" without needing a dedicated new fixture row per role).

-- ---------------------------------------------------------------------------
-- 1. school_owner can record a safeguarding concern — defaults to status
-- 'open', resolved_at null.
do $$
declare v_status public.safeguarding_status;
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.safeguarding_concerns (id, school_id, learner_id, description, severity) values
    ('7f600000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'Concern raised by a teacher', 'high');
  execute 'reset role';

  select status, resolved_at into v_status, v_resolved_at from public.safeguarding_concerns where id = '7f600000-0000-0000-0000-000000000001';
  call test_util.record('school_owner can record a safeguarding concern, defaulting to open', v_status = 'open', 'status=' || v_status);
  call test_util.record('a newly-created concern has no resolved_at', v_resolved_at is null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. principal (School A) can also see and manage it.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('77777777-7777-7777-7777-777777777777', 'principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.safeguarding_concerns where id = '7f600000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('principal can see the safeguarding concern', v_count = 1, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 3. vice_principal (has learner.view_behaviour, but NOT the narrower
-- safeguarding permission) CANNOT see it — proves the deliberately
-- narrower-than-behaviour scope.
do $$
declare v_count int;
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.safeguarding_concerns where id = '7f600000-0000-0000-0000-000000000001';
  begin
    insert into public.safeguarding_concerns (school_id, learner_id, description) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'Should not be allowed');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('vice_principal cannot see a safeguarding concern (narrower than behaviour)', v_count = 0, 'count=' || v_count);
  call test_util.record('vice_principal cannot create a safeguarding concern', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. medical_officer (has learner.view_medical, but not safeguarding)
-- also cannot see it — proves narrower than medical too.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('20202020-2020-2020-2020-202020202020', 'medical_officer', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.safeguarding_concerns where id = '7f600000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('medical_officer cannot see a safeguarding concern (narrower than medical)', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 5. A guardian can NEVER see a safeguarding concern about their own
-- linked child — zero guardian access at all, by design.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('55555555-5555-5555-5555-555555555555', 'parent', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.safeguarding_concerns where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('a guardian can never see a safeguarding concern about their own child', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. Resolving the concern auto-populates resolved_at; moving off resolved
-- clears it again.
do $$
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.safeguarding_concerns set status = 'resolved', action_taken = 'Referred to counselling' where id = '7f600000-0000-0000-0000-000000000001';
  execute 'reset role';
  select resolved_at into v_resolved_at from public.safeguarding_concerns where id = '7f600000-0000-0000-0000-000000000001';
  call test_util.record('resolving a concern auto-populates resolved_at', v_resolved_at is not null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

do $$
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.safeguarding_concerns set status = 'under_review' where id = '7f600000-0000-0000-0000-000000000001';
  execute 'reset role';
  select resolved_at into v_resolved_at from public.safeguarding_concerns where id = '7f600000-0000-0000-0000-000000000001';
  call test_util.record('re-opening a resolved concern clears resolved_at', v_resolved_at is null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 7. audit_log received an entry for the create and for each status change.
do $$
declare v_create_count int;
declare v_status_change_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  select count(*) into v_create_count from public.audit_log where entity_table = 'safeguarding_concerns' and entity_id = '7f600000-0000-0000-0000-000000000001' and action = 'safeguarding_concern_created';
  select count(*) into v_status_change_count from public.audit_log where entity_table = 'safeguarding_concerns' and entity_id = '7f600000-0000-0000-0000-000000000001' and action = 'safeguarding_concern_status_changed';
  execute 'reset role';
  call test_util.record('creating a safeguarding concern writes an audit_log entry', v_create_count = 1, 'count=' || v_create_count);
  call test_util.record('every status change writes its own audit_log entry', v_status_change_count = 2, 'count=' || v_status_change_count);
end $$;

-- ---------------------------------------------------------------------------
-- 8. Tenant isolation: School B cannot see School A's safeguarding
-- concerns.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('66666666-6666-6666-6666-666666666666', 'school_owner', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.safeguarding_concerns where school_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  execute 'reset role';
  call test_util.record('School B cannot see School A''s safeguarding concerns', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 9. The tenant-consistency trigger rejects a learner_id from a different
-- school.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('22222222-2222-2222-2222-222222222222', 'school_owner', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.safeguarding_concerns (school_id, learner_id, description) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'ffff0000-0000-0000-0000-000000000001', 'Cross-school learner');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('a learner_id belonging to a different school is rejected (or simply nonexistent)', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;
