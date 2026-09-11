-- FND-TT-003: Published/draft timetable states.
--
-- Today every timetable_entries row is immediately visible to everyone
-- with timetable.view the moment a manager saves it — there is no way to
-- stage a batch of schedule changes and reveal them to the whole school
-- at once. This adds a `status` column (draft/published) plus the RLS
-- narrowing that makes 'draft' invisible to anyone who can only view
-- (teachers, guardians) — only a manager (can_manage_academic(), the same
-- role set that can already write to this table) ever sees a draft entry.
--
-- DEFAULT 'published', not 'draft': every existing entry (and every entry
-- created through the unmodified create flow, which the UI still defaults
-- to Published) keeps behaving exactly as it does today — this is additive
-- opt-in staging capability, not a change to the existing default
-- publish-immediately behavior nothing asked to change.
--
-- Extends (does not edit) 20260826090000_timetable.sql and
-- 20260829120000_parent_portal_timetable_and_documents.sql — both already
-- relied upon by other code/tests, so their SELECT policies are dropped
-- and recreated here rather than the source files being touched, per this
-- project's own established migration convention.

create type public.timetable_entry_status as enum ('draft', 'published');

alter table public.timetable_entries add column status public.timetable_entry_status not null default 'published';

comment on column public.timetable_entries.status is 'draft = staged, visible only to managers (can_manage_academic); published = visible to everyone with timetable.view, and to guardians via the Parent Portal. Bulk-flip every draft to published via timetableService.publishDraftEntries (a plain client-side UPDATE — no new RPC needed, since the existing timetable_entries_update policy already authorizes exactly the right actor set).';

create index timetable_entries_status_idx on public.timetable_entries (school_id, academic_year_id, status);

-- Staff/teacher visibility: a manager sees every entry (draft included, so
-- they can review what they are about to publish); a viewer who cannot
-- manage only ever sees published ones.
drop policy timetable_entries_select on public.timetable_entries;
create policy timetable_entries_select on public.timetable_entries
  for select to authenticated using (
    public.can_manage_academic(school_id)
    or (public.can_view_academic(school_id) and status = 'published')
  );

-- Guardian visibility: never a draft, regardless of the existing
-- can_view_academic_reference_as_guardian() check.
drop policy timetable_entries_select_for_guardians on public.timetable_entries;
create policy timetable_entries_select_for_guardians on public.timetable_entries
  for select to authenticated using (
    public.can_view_academic_reference_as_guardian(school_id) and status = 'published'
  );
