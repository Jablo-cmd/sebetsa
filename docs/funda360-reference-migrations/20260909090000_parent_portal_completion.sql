-- Parent Portal Completion domain (1/1) — the consolidation pass that wires
-- the now-closed dependency domains into the guardian experience.
--
-- Messaging (Domain 4), Homework (Domain 5) and Report Cards (Domain 2)
-- each already shipped their own guardian-facing surface + RLS. This
-- migration adds only the one missing server-side piece: a guardian's
-- read access to the admission application(s) they submitted.
--
-- admission_applications RLS is staff-only (can_view_admissions) with no
-- guardian policy — deliberately, since an application predates any
-- account. But once a family has an account (created at conversion, or
-- pre-existing), letting them see the status of an application filed under
-- their own email address is useful and low-risk. Rather than a broad new
-- RLS policy (which would also expose the internal decision_reason /
-- resume_token / event trail), this is a narrow SECURITY DEFINER read that
-- projects only the applicant-safe columns and is scoped by
-- lower(applicant_email) = the caller's own verified profile email.

create or replace function public.get_my_admission_applications()
returns table (
  id uuid,
  school_id uuid,
  reference_number text,
  status public.admission_application_status,
  learner_first_name text,
  learner_last_name text,
  requested_grade_id uuid,
  submitted_at timestamptz,
  decision_at timestamptz,
  converted_learner_id uuid,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.school_id, a.reference_number, a.status,
         a.learner_first_name, a.learner_last_name, a.requested_grade_id,
         a.submitted_at, a.decision_at, a.converted_learner_id, a.created_at
  from public.admission_applications a
  join public.profiles p on p.id = auth.uid()
  where lower(a.applicant_email) = lower(p.email)
    and a.status <> 'draft'
  order by a.created_at desc
$$;

comment on function public.get_my_admission_applications() is
  'A guardian''s read of the admission application(s) they filed, matched by lower(applicant_email) = their own profile email. Projects only applicant-safe columns (no decision_reason / resume_token / internal event trail). Excludes drafts (a draft only ever lived in the public intake Edge Function). SECURITY DEFINER because admission_applications has no guardian RLS policy by design.';

revoke execute on function public.get_my_admission_applications() from public;
grant execute on function public.get_my_admission_applications() to authenticated;
