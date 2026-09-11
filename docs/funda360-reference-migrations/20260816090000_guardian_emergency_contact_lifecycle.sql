-- Sprint 3 Closure — Guardian & Emergency Contact removal lifecycle
--
-- learner_guardians and learner_emergency_contacts had no removal path at
-- all: no DELETE RLS policy exists on any of the six learner_* tables (see
-- 20260803190000_learner_management.sql, "combined with FORCE ROW LEVEL
-- SECURITY, hard delete is impossible for any authenticated caller"), and
-- unlike learner_documents and departments, these two tables were never
-- given an `active` archive flag either — so a mis-linked guardian or a
-- stale emergency contact could be edited but never removed. This
-- migration extends the same never-hard-delete / active=false archive
-- pattern already used by departments (20260803160000) and
-- learner_documents (20260803190000) to these two tables.
--
-- Guardian access is more than a UI convenience: is_learner_guardian() (see
-- 20260803190000) is what grants a guardian read access to a learner's
-- record, medical information and emergency contacts. If a guardian
-- relationship is archived/removed, that access must end immediately — so
-- is_learner_guardian() is redefined below to only recognise active links.

alter table public.learner_guardians add column active boolean not null default true;
alter table public.learner_emergency_contacts add column active boolean not null default true;

comment on column public.learner_guardians.active is 'Never hard-deleted — active=false is the archive/unlink state. Also immediately revokes is_learner_guardian() self-access, not just cosmetic in the UI.';
comment on column public.learner_emergency_contacts.active is 'Never hard-deleted — active=false is the archive state, same pattern as learner_documents.active.';

create index learner_guardians_learner_id_active_idx on public.learner_guardians (learner_id, active);
create index learner_emergency_contacts_learner_id_active_idx on public.learner_emergency_contacts (learner_id, active);

-- Redefined (not just "column added") so an archived guardian link loses
-- learner/medical/emergency-contact self-access immediately, not just in
-- the guardian's own UI.
create or replace function public.is_learner_guardian(p_learner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.learner_guardians
    where learner_id = p_learner_id and guardian_profile_id = auth.uid() and active
  )
$$;

comment on function public.is_learner_guardian(uuid) is
  'SECURITY DEFINER to avoid recursive RLS on learner_guardians, exactly mirroring current_tenant_id()''s reason for being SECURITY DEFINER on profiles. Used by learners_select, learner_medical_information_select and learner_emergency_contacts_select for guardian self-access. Only active (non-archived) links grant access.';

-- No RLS policy changes: learner_guardians_select / learner_emergency_contacts_select
-- (can_view_learners(school_id)) already return archived rows to staff, so
-- managers can still see and restore an archived link. INSERT/UPDATE
-- policies (can_manage_learners) already cover writing `active`, since it's
-- an ordinary column on an existing manageable row.
