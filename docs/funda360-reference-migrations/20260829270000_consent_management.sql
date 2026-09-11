-- FND-SEC-009: Consent management capture.
--
-- SCOPE, per docs/product/FUNDA360-POPIA-READINESS-BRIEF.md item 3: "POPIA's
-- lawful-processing conditions may already be satisfied via the school-
-- enrollment contract for core processing, but this needs a legal
-- determination, not an engineering guess." That legal determination is
-- NOT made here, and is explicitly out of scope for this migration — same
-- posture this session already held for FND-SEC-008 (retention policy).
-- What IS squarely engineering's job, and what this migration builds, is
-- the MECHANISM: a place to capture, view, and revoke a guardian's consent
-- for specific, genuinely discretionary processing activities, so that
-- whatever the legal review ultimately decides is required, there is
-- already a working capture/audit trail to plug it into rather than
-- nothing.
--
-- CATEGORY SCOPE — a real product/policy decision, made conservatively and
-- documented here rather than silently assumed (same discipline as
-- FND-WELL-003's role-scope note): the three categories below
-- (photo_media_use, marketing_communications, third_party_data_sharing)
-- are the ones virtually every school system captures separate,
-- affirmative consent for regardless of jurisdiction, because they are
-- clearly discretionary/optional uses layered on top of core enrollment
-- processing — NOT because a legal review has confirmed POPIA requires
-- exactly these three and no others. Deliberately excluded: a "core data
-- processing" category. Inventing an opt-in toggle for that would itself
-- be an engineering guess at a legal question the brief explicitly says
-- is unresolved — and could actively mislead a school into thinking core
-- processing is toggleable consent when the eventual legal answer may be
-- that it is contractually necessary processing requiring no separate
-- consent at all. Widening/narrowing this enum once the legal review
-- concludes is expected, low-risk future work (see the note above
-- set_updated_at's trigger below for why an enum, not free text, was
-- chosen anyway).
--
-- WHO CAN RECORD CONSENT: either the guardian themselves (self-service,
-- e.g. from the parent portal) or any staff member who can manage that
-- learner's record (e.g. capturing a paper consent form at enrollment) —
-- mirroring learner_guardians' own access shape. WHO CAN VIEW: the same,
-- plus any staff member who can merely view learners (for compliance
-- reporting), matching can_view_learners()'s existing broader read tier.
--
-- HISTORY: no separate event-log table — granted_at/revoked_at are
-- server-derived from the `granted` transition (same pattern as
-- safeguarding_concerns.resolved_at), and every transition is additionally
-- written to audit_log, matching safeguarding_concerns_audit()'s "action
-- log, not a per-SELECT access log" precedent. One current-state row per
-- (learner, guardian, category) — toggling consent updates it in place
-- rather than accumulating rows, so "what is this guardian's consent state
-- right now" is always a single unambiguous lookup.

create type public.consent_category as enum ('photo_media_use', 'marketing_communications', 'third_party_data_sharing');

create table public.consent_records (
  id                  uuid primary key default gen_random_uuid(),
  school_id           uuid not null references public.schools (id) on delete cascade,
  learner_id          uuid not null references public.learners (id) on delete cascade,
  guardian_profile_id uuid not null references public.profiles (id) on delete cascade,
  category            public.consent_category not null,
  granted             boolean not null,
  granted_at          timestamptz,
  revoked_at          timestamptz,
  notes               text,
  created_by          uuid references public.profiles (id) on delete set null,
  updated_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.consent_records is 'Current consent state per (learner, guardian, category) — see migration header for category scope and what legal question remains unresolved. Never hard-deleted (no DELETE policy); a withdrawn consent is granted=false, not a removed row, so the record of "consent was once given, then withdrawn on X date" survives.';
comment on column public.consent_records.granted_at is 'Server-derived whenever granted transitions to true — never trusted from the client, same pattern as safeguarding_concerns.resolved_at.';
comment on column public.consent_records.revoked_at is 'Server-derived whenever granted transitions to false.';

create unique index consent_records_learner_guardian_category_key on public.consent_records (learner_id, guardian_profile_id, category);
create index consent_records_school_id_idx on public.consent_records (school_id);
create index consent_records_learner_id_idx on public.consent_records (learner_id);

create trigger consent_records_set_updated_at
  before update on public.consent_records
  for each row
  execute function public.set_updated_at();

create trigger consent_records_set_created_updated_by
  before insert or update on public.consent_records
  for each row
  execute function public.set_created_updated_by();

-- Validates both that school_id matches the learner's own school (the
-- standard tenant-consistency check every child table in this schema
-- runs) AND that guardian_profile_id is a real, active guardian of that
-- specific learner — without this second check, any caller who can insert
-- at all could attach a consent record to an unrelated guardian id.
create or replace function public.consent_records_validate_links()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  if not exists (
    select 1 from public.learner_guardians
    where learner_id = new.learner_id and guardian_profile_id = new.guardian_profile_id and active
  ) then
    raise exception 'insufficient_privilege: guardian_profile_id must be an active guardian of learner_id';
  end if;

  return new;
end;
$$;

create trigger consent_records_validate_links_trigger
  before insert or update on public.consent_records
  for each row
  execute function public.consent_records_validate_links();

-- Server-derives granted_at/revoked_at from the granted transition — same
-- "server is the source of truth for a derived timestamp" pattern as
-- academic_interventions_sync_resolved_at() / safeguarding_concerns_sync_resolved_at().
create or replace function public.consent_records_sync_timestamps()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.granted and (tg_op = 'INSERT' or not old.granted) then
    new.granted_at := now();
    new.revoked_at := null;
  elsif not new.granted and (tg_op = 'INSERT' or old.granted) then
    new.revoked_at := now();
  end if;
  return new;
end;
$$;

create trigger consent_records_sync_timestamps_trigger
  before insert or update on public.consent_records
  for each row
  execute function public.consent_records_sync_timestamps();

-- Audit trail: every grant/revoke transition is written to audit_log —
-- consent state is exactly the kind of thing a future compliance review
-- needs a durable "who changed what, when" trail for, same reasoning as
-- safeguarding_concerns_audit().
create or replace function public.consent_records_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit_log(
      new.school_id, auth.uid(), 'consent_recorded', 'consent_records', new.id,
      null, jsonb_build_object('learner_id', new.learner_id, 'category', new.category, 'granted', new.granted)
    );
  elsif tg_op = 'UPDATE' and old.granted is distinct from new.granted then
    perform public.write_audit_log(
      new.school_id, auth.uid(), 'consent_changed', 'consent_records', new.id,
      jsonb_build_object('granted', old.granted), jsonb_build_object('granted', new.granted)
    );
  end if;
  return new;
end;
$$;

create trigger consent_records_audit_trigger
  after insert or update on public.consent_records
  for each row
  execute function public.consent_records_audit();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.consent_records enable row level security;
alter table public.consent_records force row level security;

create policy consent_records_select on public.consent_records
  for select to authenticated using (
    public.can_view_learners(school_id) or public.is_learner_guardian(learner_id)
  );

create policy consent_records_insert on public.consent_records
  for insert to authenticated with check (
    (public.is_learner_guardian(learner_id) and guardian_profile_id = auth.uid())
    or public.can_manage_learners(school_id)
  );

create policy consent_records_update on public.consent_records
  for update to authenticated using (
    (public.is_learner_guardian(learner_id) and guardian_profile_id = auth.uid())
    or public.can_manage_learners(school_id)
  ) with check (
    (public.is_learner_guardian(learner_id) and guardian_profile_id = auth.uid())
    or public.can_manage_learners(school_id)
  );

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete
-- is impossible for any authenticated caller (withdraw consent via
-- granted=false instead — see migration header).
