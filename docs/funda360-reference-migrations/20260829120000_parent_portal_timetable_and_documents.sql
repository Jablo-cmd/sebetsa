-- Parent Portal: timetable + document guardian visibility (FND-PAR-003 / FND-PAR-004)
--
-- parent_portal_v1 deliberately left both gaps open, for reasons specific
-- to each — this migration closes both, following the exact same
-- classification scheme parent_portal_v1 itself established.
--
-- 1. timetable_entries — treated as REFERENCE DATA, the same category as
--    grades/classes/subjects/class_teacher_assignments: a lesson slot (day,
--    time, subject, teacher, room, class) carries no personal information
--    about any specific learner, only a class-level schedule. Reuses
--    can_view_academic_reference_as_guardian(school_id), already defined
--    in parent_portal_v1 — no new function needed, just a new policy on a
--    table that migration didn't touch. timetable_entries simply didn't
--    exist yet as a concept when parent_portal_v1 was authored... it does
--    exist (20260826090000_timetable.sql, earlier) but was out of scope
--    for that pass; this migration is the deferred follow-up, not a gap
--    that was assessed and rejected.
--
-- 2. learner_documents — genuinely personal data about a specific learner,
--    same category as attendance/assessments/fees, so it gets the precise
--    is_learner_guardian(learner_id) treatment those tables have, not the
--    broader reference-data treatment. Unlike behaviour_incidents, no
--    column on this table is documented internal-staff-only commentary —
--    every learner_document_type value (birth_certificate, id_copy,
--    passport, permit, transfer_letter, medical_certificate, report_card,
--    other) is a document that either originates from the family itself or
--    is routinely shared with them, and `notes` gets exactly the same
--    unredacted treatment already given to learner_fee_charges.notes /
--    learner_fee_payments.notes in parent_portal_v1 — full-row visibility,
--    not a narrowed RPC. A matching storage.objects policy is required too
--    (the metadata row and the actual file are gated independently, same
--    split as every other bucket in this schema) — extracts learner_id
--    from path segment 2, mirroring how learner_documents_storage_select
--    extracts school_id from segment 1 for staff.

create policy timetable_entries_select_for_guardians on public.timetable_entries
  for select to authenticated using (public.can_view_academic_reference_as_guardian(school_id));

create policy learner_documents_select_for_guardians on public.learner_documents
  for select to authenticated using (public.is_learner_guardian(learner_id));

create policy learner_documents_storage_select_for_guardians
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'learner-documents'
    and public.is_learner_guardian(((storage.foldername(name))[2])::uuid)
  );
