-- ---------------------------------------------------------------------------
-- FND-SIS-007: Transfer workflow — an inter-school transfer record plus
-- (client-side) transfer letter generation. This table is deliberately just
-- the record-keeping half: "transferred" is already a real learners.status
-- value with its own validated transition (active -> transferred, per
-- learners_validate_status_transition() in 20260803190000_learner_management.sql)
-- — this table does not duplicate that state machine, it captures the
-- *details* a status change alone can't hold (which other school, whose
-- contact, when, why), for both directions:
--   outgoing — one of ours is leaving for another school
--   incoming — a new admission's own transfer history from a prior school
-- "Another school" is modeled as free text, not a foreign key to another
-- tenant's `schools` row — this platform's tenants are administratively
-- separate institutions with no shared directory of each other, and
-- linking across tenant boundaries would cut against the RLS isolation
-- model everywhere else in this schema.

create type public.learner_transfer_direction as enum ('outgoing', 'incoming');

create table public.learner_transfers (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid not null references public.schools (id) on delete cascade,
  learner_id            uuid not null references public.learners (id) on delete cascade,
  direction             public.learner_transfer_direction not null,
  other_school_name     text not null check (char_length(other_school_name) > 0),
  other_school_contact  text,
  transfer_date         date not null,
  reason                text,
  notes                 text,
  created_by            uuid references public.profiles (id) on delete set null,
  -- updated_by/updated_at exist purely so this table can reuse the shared
  -- set_created_updated_by()/set_updated_at() triggers unmodified, matching
  -- every sibling learner_* table — there is no UPDATE policy below, so in
  -- practice these never change after insert (see the SELECT/INSERT-only
  -- note further down).
  updated_by            uuid references public.profiles (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index learner_transfers_school_id_idx on public.learner_transfers (school_id);
create index learner_transfers_learner_id_idx on public.learner_transfers (learner_id);

create trigger learner_transfers_set_updated_at
  before update on public.learner_transfers
  for each row
  execute function public.set_updated_at();

create trigger learner_transfers_set_created_updated_by
  before insert or update on public.learner_transfers
  for each row
  execute function public.set_created_updated_by();

-- Same tenant-consistency guard as learner_emergency_contacts/learner_documents.
create or replace function public.learner_transfers_validate_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_learner_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_transfers.school_id must match the referenced learner''s school';
  end if;
  return new;
end;
$$;

create trigger learner_transfers_validate_tenant_trigger
  before insert on public.learner_transfers
  for each row
  execute function public.learner_transfers_validate_tenant();

alter table public.learner_transfers enable row level security;
alter table public.learner_transfers force row level security;

-- SELECT/INSERT only, matching learner_emergency_contacts/learner_documents'
-- own reasoning: a transfer record is a historical fact once entered (the
-- learner may since have transferred back, but that's a new row, not an
-- edit to this one) — no UPDATE or DELETE policy, and FORCE ROW LEVEL
-- SECURITY makes both genuinely impossible for any authenticated caller,
-- not just discouraged by the app.
create policy learner_transfers_select on public.learner_transfers
  for select to authenticated using (public.can_view_learners(school_id));
create policy learner_transfers_insert on public.learner_transfers
  for insert to authenticated with check (public.can_manage_learners(school_id));

-- No explicit grant for learner_transfers_validate_tenant(): the schema-wide
-- `alter default privileges ... revoke execute on functions from public`
-- (20260822000000_function_security_hardening.sql) already denies both
-- anon and authenticated execute on any newly created function by default,
-- and no legitimate caller should ever invoke a trigger function directly
-- anyway — same as every other trigger function added this session.
