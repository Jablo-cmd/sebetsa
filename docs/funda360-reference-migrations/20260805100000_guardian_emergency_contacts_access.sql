-- Sprint 3 Milestone 3, Phase 0 — Guardian Emergency Contact Visibility
-- (database layer only).
--
-- Background: 20260803190000_learner_management.sql's own header comment
-- on learner_emergency_contacts_select explicitly flagged this as
-- deliberately deferred, not forgotten: "The locked architecture's access
-- matrix specifies guardian/self 'own only' viewing explicitly for
-- learners and for learner_medical_information, but not explicitly for
-- these four child tables — extending self/guardian access to them was
-- not specified with the same rigor, so it is deliberately NOT
-- implemented here rather than invented. Flagged in the Phase 1 report as
-- a scoping question for a later phase, not decided by this migration."
-- This migration is that later phase, for learner_emergency_contacts only
-- — learner_enrollments, learner_guardians, and learner_documents remain
-- untouched and still staff-only, exactly as that deferral describes.
--
-- Change: extend learner_emergency_contacts_select with the same guardian
-- clause already proven on learners_select and
-- learner_medical_information_select — public.is_learner_guardian(learner_id),
-- the existing SECURITY DEFINER function built to avoid recursive-RLS
-- false negatives when checking learner_guardians from another table's
-- policy (see that function's own comment). No new function, no new
-- permission, no RBAC change — this is a straight extension of an
-- already-committed, already-tested pattern to a third table.
--
-- Staff access (public.can_view_learners(school_id)) is preserved
-- unchanged — it remains the first branch of the OR, exactly as before.
-- Learner self-access is deliberately NOT added here — the milestone
-- objective is guardian visibility only; a learner's own self-access to
-- their own emergency contacts is a separate, undecided question, and is
-- not introduced by this migration.
--
-- INSERT/UPDATE policies on this table are untouched — they still require
-- public.can_manage_learners(school_id), so this remains strictly a
-- read-only extension for guardians. Tenant isolation is unaffected: the
-- guardian clause checks caller-to-learner linkage via learner_guardians,
-- which is itself only ever created within a matching school_id (enforced
-- by that table's own tenant-match trigger), so a guardian can never be
-- linked to a learner outside their own tenant in the first place.

drop policy if exists learner_emergency_contacts_select on public.learner_emergency_contacts;

create policy learner_emergency_contacts_select on public.learner_emergency_contacts
  for select to authenticated using (
    public.can_view_learners(school_id)
    or public.is_learner_guardian(learner_id)
  );
