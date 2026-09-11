-- Parent / Guardian Portal V1 — read-only RLS foundation
--
-- Phase 1 audit finding: guardians already authenticate through the
-- existing Supabase Auth flow (admin_create_guardian() already creates a
-- real auth.users + auth.identities row, exactly like admin_create_user())
-- and is_learner_guardian() already exists as the guardian-self-access
-- mechanism. No new identity table, no new auth flow, no duplicated
-- learner-guardian relationship. This migration only fills the concrete,
-- audited gaps that block a guardian from seeing anything beyond what
-- already worked before this sprint: `learners` (identity),
-- `learner_medical_information`, and `learner_emergency_contacts` are the
-- ONLY three tables is_learner_guardian() gated before this migration —
-- confirmed by reading every SELECT policy in this schema, not assumed.
-- Attendance, assessment results/assessments, enrollments, and fee
-- charges/payments had zero guardian visibility at all.
--
-- Every policy added here is SELECT-only. Guardians gain no INSERT/UPDATE/
-- DELETE capability anywhere except their own guardian_profile_details row
-- (address/id_number self-editing — profiles.first_name/last_name/phone
-- self-editing already works today via the existing, unmodified
-- profiles_update_own policy, so it needs no change here). No existing
-- staff-facing policy, function, or role list is modified — every addition
-- below is a new, separate, additive policy, matching the exact pattern
-- already established and tested by academic_years_select_for_domain_roles
-- (20260823150000_academic_years_visibility_for_domain_roles.sql).
--
-- BEHAVIOUR IS DELIBERATELY EXCLUDED. behaviour_incidents has no column or
-- flag distinguishing guardian-appropriate information from internal
-- staff-only notes (action_taken, outcome are free-text staff commentary
-- with no visibility tier) — audited and confirmed, not assumed. Per
-- product instruction, this migration does NOT expose behaviour_incidents
-- to guardians. A future migration introducing a real visibility model
-- (e.g. a `guardian_visible` flag, or a parallel guardian-facing summary
-- table) is required before Behaviour can appear in the Parent Portal.
--
-- MEDICAL IS DELIBERATELY UNTOUCHED. learner_medical_information_select
-- already has an is_learner_guardian(learner_id) clause from
-- 20260803190000_learner_management.sql — a deliberate, already-documented
-- contract, not an accidental gap. Reused as-is; no change needed or made.
--
-- REFERENCE-DATA TABLES (grades, classes, subjects, class_teacher_assignments)
-- get a broader, simpler guardian clause (tenant + role, not per-row
-- is_learner_guardian scoping) rather than precise per-child scoping: these
-- are non-sensitive catalogue/label data (e.g. "this school has a Grade 7B
-- class taught by Mrs Smith") with no personal information attached to any
-- individual learner. Precise per-learner scoping is reserved for tables
-- that actually carry personal data about a specific learner (attendance,
-- assessment results, fees, enrolments). academic_years and terms are
-- deliberately NOT touched — the Parent Portal resolves "the child's
-- current class" via learner_enrollments.enrollment_status = 'enrolled'
-- (the same single-source-of-truth field promote_learner() maintains),
-- so no guardian access to the academic-year/term catalogue is needed for
-- V1.

-- ---------------------------------------------------------------------------
-- 1. Reference-data guardian visibility (grades/classes/subjects/class_teacher_assignments)

create or replace function public.can_view_academic_reference_as_guardian(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    target_school_id = public.current_tenant_id()
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('parent', 'guardian')
$$;

comment on function public.can_view_academic_reference_as_guardian(uuid) is
  'Guardians may read non-sensitive academic catalogue/label data (grade, class, subject names; class-teacher assignments) tenant-wide — this is not personal information about any specific learner. Deliberately simpler than is_learner_guardian()-scoped policies, which are reserved for tables that actually carry personal data about a specific learner. Keep in sync manually with the Parent Portal role set.';

grant execute on function public.can_view_academic_reference_as_guardian(uuid) to authenticated;

create policy grades_select_for_guardians on public.grades
  for select to authenticated using (public.can_view_academic_reference_as_guardian(school_id));
create policy classes_select_for_guardians on public.classes
  for select to authenticated using (public.can_view_academic_reference_as_guardian(school_id));
create policy subjects_select_for_guardians on public.subjects
  for select to authenticated using (public.can_view_academic_reference_as_guardian(school_id));
create policy class_teacher_assignments_select_for_guardians on public.class_teacher_assignments
  for select to authenticated using (public.can_view_academic_reference_as_guardian(school_id));

-- ---------------------------------------------------------------------------
-- 2. Learner-specific guardian visibility — precise is_learner_guardian(learner_id)
-- scoping, identical shape to the already-tested learner_medical_information
-- and learner_emergency_contacts guardian clauses.

create policy learner_enrollments_select_for_guardians on public.learner_enrollments
  for select to authenticated using (public.is_learner_guardian(learner_id));

create policy attendance_records_select_for_guardians on public.attendance_records
  for select to authenticated using (public.is_learner_guardian(learner_id));

create policy assessment_results_select_for_guardians on public.assessment_results
  for select to authenticated using (public.is_learner_guardian(learner_id));

-- assessments itself has no learner_id (it's scoped to class+subject+term,
-- not to an individual learner) — a guardian may see an assessment's
-- definition (title/type/date/max_mark) only if their own linked learner
-- has an actual result recorded against it. This is a plain EXISTS
-- subquery, not a new SECURITY DEFINER wrapper: assessment_results_select
-- (see above) already grants the guardian direct row-level visibility into
-- their own linked learner's assessment_results rows, so this subquery
-- evaluates correctly under the guardian's own session — unlike
-- is_learner_guardian()'s own reason for being SECURITY DEFINER (querying
-- learner_guardians, which has NO guardian-accessible SELECT clause at
-- all), there is no recursive-RLS false-negative risk here.
create policy assessments_select_for_guardians on public.assessments
  for select to authenticated using (
    exists (
      select 1 from public.assessment_results ar
      where ar.assessment_id = assessments.id
        and public.is_learner_guardian(ar.learner_id)
    )
  );

create policy learner_fee_charges_select_for_guardians on public.learner_fee_charges
  for select to authenticated using (public.is_learner_guardian(learner_id));

create policy learner_fee_payments_select_for_guardians on public.learner_fee_payments
  for select to authenticated using (public.is_learner_guardian(learner_id));

-- ---------------------------------------------------------------------------
-- 3. Guardian self-access to their own guardian_profile_details row
-- (address / ID-reference number) — "My Profile" self-service editing.
-- profiles.first_name/last_name/phone self-editing already works via the
-- existing, unmodified profiles_update_own policy (20260802125403), so
-- this migration only needs to extend the ONE table that didn't already
-- have a self-access clause. A guardian may only ever touch their OWN row
-- (guardian_profile_id = auth.uid()) — never another guardian's, and never
-- the relationship rows in learner_guardians itself (unchanged, still
-- staff-only can_manage_learners()), so a guardian can never link
-- themselves to a learner or alter their own relationship metadata.

create policy guardian_profile_details_select_own on public.guardian_profile_details
  for select to authenticated using (guardian_profile_id = auth.uid());

create policy guardian_profile_details_update_own on public.guardian_profile_details
  for update to authenticated using (guardian_profile_id = auth.uid()) with check (guardian_profile_id = auth.uid());

-- No INSERT-own policy: a guardian's guardian_profile_details row (if any)
-- is created by staff via admin_create_guardian() or the Guardian
-- Management UI, not self-service — matches "a guardian should not be able
-- to link themselves to another learner" in spirit: guardians edit existing
-- data about themselves, they do not create new relationship-adjacent rows.
