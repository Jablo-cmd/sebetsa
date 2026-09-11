-- Attendance Domain — RLS Hardening (Sprint 6 verification pass)
--
-- 20260817120000_attendance.sql shipped without ever being run against the
-- Docker RLS regression harness (Docker was unavailable at the time — see
-- that sprint's own report). Docker remains unavailable in this
-- environment too, so this migration is the result of a careful manual
-- trace through every RLS policy this feature's code paths actually touch
-- — not an assumption — which surfaced two real defects, both fixed below,
-- plus the policy extension needed to make the feature actually work for
-- its primary user.
--
-- DEFECT 1 — teachers could never actually save attendance in production.
-- attendance_records_validate_tenant() was a plain (SECURITY INVOKER)
-- function, so its internal `select ... from public.learners where id =
-- new.learner_id` ran under the CALLING role's own RLS. learners_select
-- only grants visibility via can_view_learners() (school_owner, principal,
-- admissions_officer, medical_officer), or self/guardian access — a
-- teacher recording attendance for their own class's students satisfies
-- none of those clauses, so the lookup silently returned zero rows,
-- leaving the local variable NULL, which the trigger's `is distinct from
-- new.school_id` check then treated as a mismatch — raising
-- "insufficient_privilege: learner_id must belong to the same school" for
-- every single teacher-submitted record, regardless of whether it was
-- actually correct. This was invisible to this app's e2e suite, which is
-- fully network-mocked and never executes real Postgres/RLS.
-- class_teacher_assignments_validate_tenant() (20260817090000) never hit
-- this because none of its lookups (academic_years/classes/subjects/
-- profiles) are gated behind a permission teachers lack — attendance is
-- the first trigger of this shape to touch `learners`, which is.
-- Fix: mark the function SECURITY DEFINER (set search_path = public, the
-- same convention current_tenant_id()/is_learner_guardian() already use
-- for exactly this class of problem) so its tenant-consistency checks run
-- with full visibility regardless of the caller's own view permissions.
-- This is safe — the function only ever raises an exception or passes
-- silently; it returns no row data to the caller, so there is no new
-- information disclosure. It is a strict improvement: previously the
-- check "worked" only by accident for school_owner/principal (who do have
-- learner visibility) and was simply broken for teachers; now it works
-- correctly and uniformly for every role, including correctly rejecting
-- genuine cross-tenant references it could never actually evaluate before.
--
-- DEFECT 2 — nothing enforced that the learner an attendance row names is
-- actually enrolled in the class it names. can_record_attendance() only
-- checks "is this class one you're allowed to touch" — a teacher assigned
-- to class A (or a school_owner/principal, broadly) could submit an
-- attendance row for ANY learner_id in the school under class_id=A, as
-- long as school_id/class_id/academic_year_id/learner_id each
-- individually belonged to the same school. The application's own UI
-- never does this (attendanceService.saveAttendance only ever submits
-- learner ids that came from getClassRoster's own enrolled-learners
-- query), but RLS/triggers exist precisely to defend against something
-- other than the app's own UI — a valid teacher session hitting the REST
-- API directly. Fix: extend the (now SECURITY DEFINER) validate-tenant
-- trigger to also require an 'enrolled' learner_enrollments row for
-- (learner_id, class_id, academic_year_id). This simultaneously closes
-- the "wrong learner" gap and strengthens duplicate-prevention at a
-- semantic level — since a learner only ever has one class_id per
-- academic year (learner_enrollments is unique per (learner_id,
-- academic_year_id)), a given learner can now only ever get attendance
-- rows under the one class_id they're actually enrolled in, eliminating
-- any possibility of the same learner accumulating "duplicate-but-
-- technically-distinct" rows for the same day under two different
-- class_id values.
--
-- SIDE EFFECT NEEDED TO MAKE THE FEATURE ACTUALLY WORK — the same
-- learners_select/learner_enrollments_select gap that broke the trigger
-- also breaks attendanceService.getClassRoster() itself: it queries
-- learner_enrollments then learners directly from the client, so under
-- real RLS a teacher's roster fetch silently returns an EMPTY array (RLS
-- filters rows, it does not raise an error on SELECT) — indistinguishable
-- in the UI from a genuinely empty class ("No learners enrolled in this
-- class yet."). Fixed by extending both policies with a new, narrowly
-- class-scoped visibility clause for teacher-variant roles — NOT by
-- granting them learner.view, which would be a much broader change than
-- this defect calls for and would affect every other learner-related
-- surface in the app. The new learners_select clause needs a SECURITY
-- DEFINER helper (is_teacher_of_enrolled_learner) for the same
-- recursive-RLS reason is_learner_guardian() already documents: a plain
-- inline subquery against learner_enrollments from within learners_select
-- would itself be re-evaluated under learner_enrollments' own RLS for the
-- same calling teacher, who fails that table's can_view_learners() gate
-- too, producing the exact same false-negative failure mode all over
-- again. The learner_enrollments_select extension does NOT need a
-- wrapper — its new clause only queries class_teacher_assignments, which
-- teachers already see via can_view_academic().

create or replace function public.is_teacher_of_enrolled_learner(p_learner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.learner_enrollments le
    join public.class_teacher_assignments cta on cta.class_id = le.class_id
    where le.learner_id = p_learner_id
      and le.enrollment_status = 'enrolled'
      and cta.teacher_profile_id = auth.uid()
      and cta.active
  )
$$;

comment on function public.is_teacher_of_enrolled_learner(uuid) is
  'SECURITY DEFINER to avoid recursive RLS on learner_enrollments, exactly mirroring is_learner_guardian()''s reason for being SECURITY DEFINER on learner_guardians. Lets a teacher see (read-only) the roster of a class they are actively assigned to, without granting the broader learner.view permission.';

grant execute on function public.is_teacher_of_enrolled_learner(uuid) to authenticated;

drop policy if exists learners_select on public.learners;
create policy learners_select on public.learners
  for select to authenticated using (
    public.can_view_learners(school_id)
    or profile_id = auth.uid()
    or public.is_learner_guardian(id)
    or public.is_teacher_of_enrolled_learner(id)
  );

drop policy if exists learner_enrollments_select on public.learner_enrollments;
create policy learner_enrollments_select on public.learner_enrollments
  for select to authenticated using (
    public.can_view_learners(school_id)
    or exists (
      select 1 from public.class_teacher_assignments cta
      where cta.class_id = learner_enrollments.class_id
        and cta.teacher_profile_id = auth.uid()
        and cta.active
    )
  );

-- Defect 1 + Defect 2 fix, combined into the one trigger function.
create or replace function public.attendance_records_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year_school_id uuid;
  v_class_school_id uuid;
  v_learner_school_id uuid;
  v_enrolled boolean;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id into v_class_school_id from public.classes where id = new.class_id;
  if v_class_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: class_id must belong to the same school';
  end if;

  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select exists (
    select 1 from public.learner_enrollments
    where learner_id = new.learner_id
      and class_id = new.class_id
      and academic_year_id = new.academic_year_id
      and enrollment_status = 'enrolled'
  ) into v_enrolled;
  if not v_enrolled then
    raise exception 'insufficient_privilege: learner_id must be actively enrolled in class_id for academic_year_id';
  end if;

  return new;
end;
$$;
