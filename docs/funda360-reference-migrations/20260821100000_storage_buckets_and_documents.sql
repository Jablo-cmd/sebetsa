-- Real Supabase Storage — school logo + learner documents
--
-- Closes a pre-existing gap the Phase 1 audit flagged: `schools.logo_url`
-- and `learner_documents.file_url` were both pasted-URL text fields with
-- nothing actually stored by Funda360. Neither column is renamed here —
-- both are reused to hold a Storage OBJECT PATH instead of an external
-- URL, so no data migration is needed and every existing FK/type/service
-- shape stays exactly as it was. The application layer (src/lib/storage.ts
-- + schoolService.ts/documentService.ts) resolves a path to a short-lived
-- signed URL on demand — nothing is ever served from a public bucket.
--
-- Two buckets, both private, both size/mime-limited server-side by the
-- Storage API itself (defense in depth alongside client-side validation):
--   school-logos      — {school_id}/logo, fixed path + upsert:true, so a
--                        re-upload overwrites in place and can never
--                        orphan a previous file.
--   learner-documents — {school_id}/{learner_id}/{uuid}-{filename},
--                        additive-only — matches learner_documents' own
--                        existing "never hard delete, active=false is the
--                        archive state" design, so an archived document's
--                        file is deliberately kept, not deleted. No DELETE
--                        storage policy exists on either bucket for the
--                        same reason the underlying tables have no DELETE
--                        RLS policy — this is the established pattern
--                        every other domain in this schema already uses,
--                        not a new one invented for Storage.
--
-- Every storage.objects policy below calls the SAME can_manage_school() /
-- can_view_learners() / can_manage_learners() functions the corresponding
-- table's own RLS policies already call — file access and row access are
-- authorized by construction from one shared source of truth, not two
-- independently-maintained rulesets that could drift apart.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('school-logos', 'school-logos', false, 2097152, array['image/png', 'image/jpeg', 'image/webp']),
  ('learner-documents', 'learner-documents', false, 15728640, array['application/pdf', 'image/jpeg', 'image/png']);

comment on column public.schools.logo_url is 'Storage object path within the school-logos bucket (e.g. "<school_id>/logo"), resolved to a signed URL by schoolService.ts — not a directly-usable URL. NULL if no logo has been uploaded.';
comment on column public.learner_documents.file_url is 'Storage object path within the learner-documents bucket (e.g. "<school_id>/<learner_id>/<uuid>-<filename>"), resolved to a signed URL by documentService.ts — not a directly-usable URL.';

-- ---------------------------------------------------------------------------
-- school-logos: path segment 1 = school_id. Any member of that tenant may
-- view the logo (mirrors schools_select_within_tenant_or_platform_admin —
-- a school's own branding isn't sensitive to its own staff); only
-- can_manage_school() (school_owner/principal, or a platform admin) may
-- upload/replace it, mirroring schools_update_by_management_or_platform_admin
-- exactly.

create policy school_logos_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'school-logos'
    and (
      ((storage.foldername(name))[1])::uuid = public.current_tenant_id()
      or public.is_platform_admin()
    )
  );

create policy school_logos_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'school-logos'
    and public.can_manage_school(((storage.foldername(name))[1])::uuid)
  );

create policy school_logos_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'school-logos'
    and public.can_manage_school(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'school-logos'
    and public.can_manage_school(((storage.foldername(name))[1])::uuid)
  );

-- ---------------------------------------------------------------------------
-- learner-documents: path segment 1 = school_id. Same view/manage split as
-- the learner_documents table itself — can_view_learners() to read,
-- can_manage_learners() to upload. No self/guardian/teacher access, for
-- the same reason the table's own SELECT policy has none yet (see
-- 20260803190000_learner_management.sql's comment on this table — a
-- deliberately deferred scoping question, not an oversight).

create policy learner_documents_storage_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'learner-documents'
    and public.can_view_learners(((storage.foldername(name))[1])::uuid)
  );

create policy learner_documents_storage_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'learner-documents'
    and public.can_manage_learners(((storage.foldername(name))[1])::uuid)
  );

create policy learner_documents_storage_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'learner-documents'
    and public.can_manage_learners(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'learner-documents'
    and public.can_manage_learners(((storage.foldername(name))[1])::uuid)
  );
