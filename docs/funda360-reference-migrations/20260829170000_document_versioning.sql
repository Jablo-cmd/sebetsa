-- Learner document versioning (FND-SIS-009, second half — expiry_date was
-- already delivered by FND-DOC-002)
--
-- learner_documents already never hard-deletes (active=false is the
-- archive state) and already allows multiple rows of the same
-- document_type per learner (no uniqueness constraint ties them
-- together) — so re-uploading a renewed passport already preserved
-- history by construction, it just had no explicit link between "this new
-- upload" and "the document it renews". supersedes_document_id adds that
-- link: when set, the trigger below archives the superseded row
-- automatically (the point of "replacing" a document is that the old one
-- stops being the current one), so staff don't have to remember a second,
-- separate archive step.
--
-- Deliberately not restricted to the same document_type — a school
-- sometimes moves from one proof-of-identity document to another (e.g. a
-- permit superseded by a passport), and the schema already treats
-- document_type as free-form-enough (see fees_domain's own precedent of
-- not over-constraining categorical fields) that requiring a type match
-- here would be a rule this codebase doesn't actually need enforced.

alter table public.learner_documents
  add column supersedes_document_id uuid references public.learner_documents (id) on delete set null;

comment on column public.learner_documents.supersedes_document_id is 'Set when this upload is an explicit renewal/replacement of an earlier document — the referenced row is auto-archived (active=false) by learner_documents_archive_superseded(). Nullable: most uploads are not a renewal of anything. Not required to match document_type.';

create or replace function public.learner_documents_archive_superseded()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.supersedes_document_id is not null then
    if not exists (
      select 1 from public.learner_documents
      where id = new.supersedes_document_id and learner_id = new.learner_id
    ) then
      raise exception 'insufficient_privilege: supersedes_document_id must reference a document belonging to the same learner';
    end if;

    update public.learner_documents
    set active = false
    where id = new.supersedes_document_id;
  end if;

  return new;
end;
$$;

comment on function public.learner_documents_archive_superseded() is 'AFTER INSERT trigger — when a new document names an earlier one via supersedes_document_id, that earlier row is archived (active=false) in the same transaction. SECURITY DEFINER only because the cross-row UPDATE would otherwise need can_manage_learners() re-evaluated against a row already covered by this INSERT''s own authorization; the same-learner check above is the real safety boundary, not a broadened permission grant.';

create trigger learner_documents_archive_superseded_trigger
  after insert on public.learner_documents
  for each row
  execute function public.learner_documents_archive_superseded();
