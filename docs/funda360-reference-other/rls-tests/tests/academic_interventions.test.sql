-- Regression suite for FND-ACA-006 (20260829190000_academic_interventions.sql):
-- the academic_interventions table, its RLS (can_view_academic_intervention/
-- can_manage_academic_intervention), tenant-consistency trigger, and the
-- server-side resolved_at sync. Reuses School A/B, learner A1
-- (11110000...0001, 05_learner_fixtures.sql) and academic year
-- aaaa1111...0001 (03_academic_fixtures.sql) — no dedicated isolation
-- fixture needed, since this table carries no exact-count assertion
-- anywhere else in the suite.

-- ---------------------------------------------------------------------------
-- 1. A teacher (has assessment.manage, mirrored by can_manage_academic_
-- intervention) can record an intervention for learner A1, defaulting to
-- status='open' with resolved_at left null.
do $$
declare v_status public.academic_intervention_status;
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  insert into public.academic_interventions (id, school_id, learner_id, academic_year_id, title, description) values
    ('ac000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Extra Mathematics support', 'Struggling with fractions this term');

  execute 'reset role';

  select status, resolved_at into v_status, v_resolved_at from public.academic_interventions where id = 'ac000000-0000-0000-0000-000000000001';
  call test_util.record('a teacher can record an intervention, defaulting to open', v_status = 'open', 'status=' || v_status);
  call test_util.record('a newly-created intervention has no resolved_at', v_resolved_at is null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. Transitioning status to 'resolved' auto-populates resolved_at server-side.
do $$
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.academic_interventions set status = 'resolved', resolution_notes = 'Caught up after extra sessions' where id = 'ac000000-0000-0000-0000-000000000001';
  execute 'reset role';

  select resolved_at into v_resolved_at from public.academic_interventions where id = 'ac000000-0000-0000-0000-000000000001';
  call test_util.record('resolving an intervention auto-populates resolved_at', v_resolved_at is not null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. Moving it back off 'resolved' clears resolved_at again (never a stale
-- leftover timestamp once un-resolved).
do $$
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.academic_interventions set status = 'in_progress' where id = 'ac000000-0000-0000-0000-000000000001';
  execute 'reset role';

  select resolved_at into v_resolved_at from public.academic_interventions where id = 'ac000000-0000-0000-0000-000000000001';
  call test_util.record('un-resolving an intervention clears resolved_at', v_resolved_at is null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. hr_manager (no assessment.manage, no learner.manage) can neither view
-- nor create academic interventions.
do $$
declare v_count int;
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('88888888-8888-8888-8888-888888888888', 'hr_manager', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';

  select count(*) into v_count from public.academic_interventions where learner_id = '11110000-0000-0000-0000-000000000001';

  begin
    insert into public.academic_interventions (school_id, learner_id, academic_year_id, title) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'Should not be allowed');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;

  execute 'reset role';

  call test_util.record('hr_manager cannot view academic interventions', v_count = 0, 'count=' || v_count);
  call test_util.record('hr_manager cannot create an academic intervention', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. Tenant isolation: School B cannot see School A's interventions.
do $$
declare v_count int;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('33333333-3333-3333-3333-333333333333', 'teacher', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.academic_interventions where learner_id = '11110000-0000-0000-0000-000000000001';
  execute 'reset role';
  call test_util.record('School B cannot see School A''s academic interventions', v_count = 0, 'count=' || v_count);
end $$;

-- ---------------------------------------------------------------------------
-- 6. The tenant-consistency trigger rejects an academic_year_id from a
-- different school.
do $$
declare v_error text;
declare v_ok boolean := false;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  begin
    insert into public.academic_interventions (school_id, learner_id, academic_year_id, title) values
      ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'bbbb1111-0000-0000-0000-000000000001', 'Mismatched academic year');
  exception when others then
    get stacked diagnostics v_error = message_text;
    v_ok := true;
  end;
  execute 'reset role';
  call test_util.record('an academic_year_id from a different school is rejected', v_ok, coalesce(v_error, 'INSERT succeeded unexpectedly'));
end $$;
