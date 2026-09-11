-- Regression suite for FND-WELL-004 (20260829250000_behaviour_follow_up_tracking.sql):
-- the structured follow_up_status/follow_up_assigned_to/follow_up_target_date
-- columns on behaviour_incidents, and the follow_up_resolved_at sync
-- trigger. No new RLS policy exists for this migration (new columns on an
-- existing row, covered by behaviour_incidents' existing policies) — this
-- suite exists to prove that coverage actually holds for the new columns
-- specifically, not just assume it.
--
-- Uses the same fixtures as behaviour.test.sql: vice_principal 14141414,
-- teacher 11111111, learner 11110000...0001, academic year
-- aaaa1111...0001 (all School A).

-- ---------------------------------------------------------------------------
-- 1. vice_principal records an incident with a follow-up, assigns it to
-- themselves, and sets a target date — defaults to not_started with no
-- resolved_at.
do $$
declare v_status public.behaviour_follow_up_status;
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  insert into public.behaviour_incidents (id, school_id, learner_id, academic_year_id, incident_type, severity, description, follow_up_required, follow_up_assigned_to, follow_up_target_date)
    values ('7f700000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11110000-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000001', 'negative', 'medium', 'Repeated lateness', true, '14141414-1414-1414-1414-141414141414', '2026-09-15');
  execute 'reset role';

  select follow_up_status, follow_up_resolved_at into v_status, v_resolved_at from public.behaviour_incidents where id = '7f700000-0000-0000-0000-000000000001';
  call test_util.record('a new follow-up defaults to not_started', v_status = 'not_started', 'status=' || v_status);
  call test_util.record('a new follow-up has no resolved_at', v_resolved_at is null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. Moving the follow-up to resolved auto-populates follow_up_resolved_at.
do $$
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.behaviour_incidents set follow_up_status = 'resolved' where id = '7f700000-0000-0000-0000-000000000001';
  execute 'reset role';
  select follow_up_resolved_at into v_resolved_at from public.behaviour_incidents where id = '7f700000-0000-0000-0000-000000000001';
  call test_util.record('resolving the follow-up auto-populates follow_up_resolved_at', v_resolved_at is not null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 3. Re-opening it clears follow_up_resolved_at again.
do $$
declare v_resolved_at timestamptz;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('14141414-1414-1414-1414-141414141414', 'vice_principal', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.behaviour_incidents set follow_up_status = 'in_progress' where id = '7f700000-0000-0000-0000-000000000001';
  execute 'reset role';
  select follow_up_resolved_at into v_resolved_at from public.behaviour_incidents where id = '7f700000-0000-0000-0000-000000000001';
  call test_util.record('re-opening the follow-up clears follow_up_resolved_at', v_resolved_at is null, 'resolved_at=' || coalesce(v_resolved_at::text, '(null)'));
end $$;

-- ---------------------------------------------------------------------------
-- 4. A teacher (no learner.manage_behaviour) cannot update the follow-up
-- fields either — the existing behaviour_incidents_update policy already
-- covers the new columns, confirmed rather than assumed.
do $$
declare v_status public.behaviour_follow_up_status;
begin
  perform set_config('request.jwt.claims',
    test_util.jwt_claims('11111111-1111-1111-1111-111111111111', 'teacher', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
  execute 'set local role authenticated';
  update public.behaviour_incidents set follow_up_status = 'resolved' where id = '7f700000-0000-0000-0000-000000000001';
  execute 'reset role';
  select follow_up_status into v_status from public.behaviour_incidents where id = '7f700000-0000-0000-0000-000000000001';
  call test_util.record('a teacher cannot update a behaviour incident''s follow-up status', v_status = 'in_progress', 'status=' || v_status);
end $$;
