-- FND-WELL-004: Structured intervention/case tracking for behaviour
-- follow-ups.
--
-- GAP (documented in docs/product/FUNDA360-CURRENT-STATE.md before this
-- migration): behaviour_incidents.follow_up_required/follow_up_notes are
-- a boolean and a free-text field set once at creation — there is no way
-- to mark a follow-up done, assign it to a specific staff member, give it
-- a target date, or track its own status independent of the incident
-- itself. This migration turns that into a real, structured mini-workflow
-- while keeping it as columns on the SAME behaviour_incidents row, not a
-- new child table — a behaviour incident has at most one follow-up
-- thread, unlike academic_interventions (FND-ACA-006) or
-- safeguarding_concerns (FND-WELL-003), both of which are legitimately
-- many-per-learner independent of any single triggering event. Adding a
-- table (and a join) for an inherently 1:1 relationship would be the same
-- kind of unnecessary complexity this codebase's own standing instruction
-- explicitly warns against.
--
-- No new RLS policy is needed — these are new columns on an existing row,
-- automatically covered by behaviour_incidents' existing
-- can_view_behaviour()/can_manage_behaviour() policies.
--
-- follow_up_resolved_at is server-derived from follow_up_status, same
-- "server is the source of truth for a derived timestamp" pattern as
-- academic_interventions.resolved_at/safeguarding_concerns.resolved_at.

create type public.behaviour_follow_up_status as enum ('not_started', 'in_progress', 'resolved');

alter table public.behaviour_incidents
  add column follow_up_status public.behaviour_follow_up_status not null default 'not_started',
  add column follow_up_assigned_to uuid references public.profiles (id) on delete set null,
  add column follow_up_target_date date,
  add column follow_up_resolved_at timestamptz;

comment on column public.behaviour_incidents.follow_up_status is 'Independent of the incident''s own active flag — a follow-up can be tracked to resolution long after the incident itself is on file. Meaningful only when follow_up_required is true, but not constrained to that by a CHECK — a school marking progress on a follow-up it later decides wasn''t formally "required" is harmless.';
comment on column public.behaviour_incidents.follow_up_assigned_to is 'The staff member responsible for the follow-up — any profile, not restricted to a teaching role (matches created_by''s own unrestricted-profile convention).';
comment on column public.behaviour_incidents.follow_up_resolved_at is 'Server-derived whenever follow_up_status transitions to/from resolved — never trusted from the client, same pattern as academic_interventions.resolved_at.';

create index behaviour_incidents_follow_up_status_idx on public.behaviour_incidents (school_id, follow_up_status) where follow_up_required;
create index behaviour_incidents_follow_up_assigned_to_idx on public.behaviour_incidents (follow_up_assigned_to) where follow_up_assigned_to is not null;

create or replace function public.behaviour_incidents_sync_follow_up_resolved_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.follow_up_status = 'resolved' and (tg_op = 'INSERT' or old.follow_up_status is distinct from 'resolved') then
    new.follow_up_resolved_at := now();
  elsif new.follow_up_status is distinct from 'resolved' then
    new.follow_up_resolved_at := null;
  end if;
  return new;
end;
$$;

create trigger behaviour_incidents_sync_follow_up_resolved_at_trigger
  before insert or update on public.behaviour_incidents
  for each row
  execute function public.behaviour_incidents_sync_follow_up_resolved_at();
