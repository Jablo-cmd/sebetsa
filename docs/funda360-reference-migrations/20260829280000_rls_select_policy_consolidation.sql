-- FND-QA-002 finding: consolidate paired permissive SELECT policies to fix
-- a real, severe, load-only-visible performance defect.
--
-- HOW THIS WAS FOUND: a new load-test tool (supabase/load-tests/run.mjs)
-- driving 20 concurrent virtual users (real seeded Auris Academy accounts
-- across roles) against the real local Supabase instance showed
-- assessments_list averaging ~7.7s with a 48% error/timeout rate under
-- concurrency, versus 375-735ms for every other scenario. `EXPLAIN
-- ANALYZE` with RLS actually engaged (not bypassed as postgres/superuser)
-- showed why: `assessments` carries two separate PERMISSIVE SELECT
-- policies — assessments_select (cheap: can_view_academic(school_id), a
-- pure JWT-claim check) and assessments_select_for_guardians (an EXISTS
-- against assessment_results calling is_learner_guardian() per row).
-- Multiple permissive policies for the same command are combined by
-- Postgres as an OR of their quals — but the planner chose to implement
-- that OR via a hashed subplan that unconditionally materializes a full
-- sequential scan of assessment_results (calling the SECURITY DEFINER
-- is_learner_guardian() for every one of its rows) BEFORE evaluating the
-- cheap can_view_academic() check, for every single call, regardless of
-- caller role. Verified directly: 1393ms execution as a real principal
-- (who should short-circuit instantly on can_view_academic() = true)
-- dropped to 18.6ms — a ~75x improvement, with the guardian subplan
-- showing "never executed" — once both policies were merged into ONE
-- permissive policy with the cheap check listed first. Guardian-path
-- correctness was independently verified unaffected (still exactly the
-- rows a real guardian should see) — this migration changes policy
-- STRUCTURE only, not access logic; every merged qual below is the
-- verbatim original condition from both source policies, just combined
-- into a single USING clause instead of two separate policies.
--
-- SCOPE: `pg_policies` was queried for every table carrying more than one
-- permissive SELECT policy (17 tables). Of those, this migration touches
-- the 14 where the second policy calls a genuinely non-trivial function
-- (is_learner_guardian() — a real table lookup — or, for `assessments`,
-- a cross-table EXISTS) — i.e. every table actually exposed to this
-- failure mode. Two tables were deliberately EXCLUDED as out of scope,
-- not overlooked:
--   - academic_years: both of its two policies (can_view_academic /
--     can_view_academic_years_for_domain_roles) are pure JWT-claim
--     checks with no table access at all — nothing to short-circuit,
--     no risk.
--   - guardian_profile_details: its second policy is a plain
--     `guardian_profile_id = auth.uid()` column comparison, not a
--     function call — trivially cheap regardless of evaluation order.
-- `storage.objects` (3 permissive policies, learner document/school logo
-- storage) was also left untouched — a different subsystem (bucket-path
-- based conditions), lower likely severity (per-folder listings, not
-- full-table scans), and higher risk of subtly misreading its
-- bucket-path logic under this session's time budget; a candidate for a
-- dedicated follow-up if it shows up in a future load test, not silently
-- assumed fine.
--
-- Every change below is: drop the table's two existing permissive SELECT
-- policies, create one new policy with the identical name as the
-- table's original primary policy (e.g. assessments_select), whose
-- USING clause is `<original staff qual> or <original guardian qual>`
-- with the cheap staff-facing check listed first (verified to matter —
-- see above). INSERT/UPDATE/DELETE policies on every one of these tables
-- are completely untouched.

-- ---------------------------------------------------------------------------
drop policy if exists assessment_results_select on public.assessment_results;
drop policy if exists assessment_results_select_for_guardians on public.assessment_results;
create policy assessment_results_select on public.assessment_results
  for select to authenticated using (
    can_view_academic(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists assessments_select on public.assessments;
drop policy if exists assessments_select_for_guardians on public.assessments;
create policy assessments_select on public.assessments
  for select to authenticated using (
    can_view_academic(school_id)
    or exists (
      select 1 from public.assessment_results ar
      where ar.assessment_id = assessments.id and is_learner_guardian(ar.learner_id)
    )
  );

-- ---------------------------------------------------------------------------
drop policy if exists attendance_records_select on public.attendance_records;
drop policy if exists attendance_records_select_for_guardians on public.attendance_records;
create policy attendance_records_select on public.attendance_records
  for select to authenticated using (
    can_view_academic(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists class_teacher_assignments_select on public.class_teacher_assignments;
drop policy if exists class_teacher_assignments_select_for_guardians on public.class_teacher_assignments;
create policy class_teacher_assignments_select on public.class_teacher_assignments
  for select to authenticated using (
    can_view_academic(school_id) or can_view_academic_reference_as_guardian(school_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists classes_select on public.classes;
drop policy if exists classes_select_for_guardians on public.classes;
create policy classes_select on public.classes
  for select to authenticated using (
    can_view_academic(school_id) or can_view_academic_reference_as_guardian(school_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists grades_select on public.grades;
drop policy if exists grades_select_for_guardians on public.grades;
create policy grades_select on public.grades
  for select to authenticated using (
    can_view_academic(school_id) or can_view_academic_reference_as_guardian(school_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists learner_documents_select on public.learner_documents;
drop policy if exists learner_documents_select_for_guardians on public.learner_documents;
create policy learner_documents_select on public.learner_documents
  for select to authenticated using (
    can_view_learners(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists learner_enrollments_select on public.learner_enrollments;
drop policy if exists learner_enrollments_select_for_guardians on public.learner_enrollments;
create policy learner_enrollments_select on public.learner_enrollments
  for select to authenticated using (
    can_view_learners(school_id)
    or exists (
      select 1 from public.class_teacher_assignments cta
      where cta.class_id = learner_enrollments.class_id and cta.teacher_profile_id = auth.uid() and cta.active
    )
    or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists learner_fee_adjustments_select on public.learner_fee_adjustments;
drop policy if exists learner_fee_adjustments_select_for_guardians on public.learner_fee_adjustments;
create policy learner_fee_adjustments_select on public.learner_fee_adjustments
  for select to authenticated using (
    can_view_learner_financial(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists learner_fee_charges_select on public.learner_fee_charges;
drop policy if exists learner_fee_charges_select_for_guardians on public.learner_fee_charges;
create policy learner_fee_charges_select on public.learner_fee_charges
  for select to authenticated using (
    can_view_learner_financial(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists learner_fee_payments_select on public.learner_fee_payments;
drop policy if exists learner_fee_payments_select_for_guardians on public.learner_fee_payments;
create policy learner_fee_payments_select on public.learner_fee_payments
  for select to authenticated using (
    can_view_learner_financial(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists learner_fee_refunds_select on public.learner_fee_refunds;
drop policy if exists learner_fee_refunds_select_for_guardians on public.learner_fee_refunds;
create policy learner_fee_refunds_select on public.learner_fee_refunds
  for select to authenticated using (
    can_view_learner_financial(school_id) or is_learner_guardian(learner_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists subjects_select on public.subjects;
drop policy if exists subjects_select_for_guardians on public.subjects;
create policy subjects_select on public.subjects
  for select to authenticated using (
    can_view_academic(school_id) or can_view_academic_reference_as_guardian(school_id)
  );

-- ---------------------------------------------------------------------------
drop policy if exists timetable_entries_select on public.timetable_entries;
drop policy if exists timetable_entries_select_for_guardians on public.timetable_entries;
create policy timetable_entries_select on public.timetable_entries
  for select to authenticated using (
    (can_manage_academic(school_id) or (can_view_academic(school_id) and status = 'published'))
    or (can_view_academic_reference_as_guardian(school_id) and status = 'published')
  );
