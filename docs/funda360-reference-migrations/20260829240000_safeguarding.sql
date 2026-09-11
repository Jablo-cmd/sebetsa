-- FND-WELL-003: Safeguarding/counselling workflow.
--
-- STAKES: reclassified P2 -> P1 specifically for this reason (per the
-- Kanban's own note) — this table holds concerns about a minor's safety,
-- a materially higher-sensitivity category of data than behaviour
-- incidents or medical information, both of which already have their own
-- narrower-than-general-staff access models in this schema. This
-- migration deliberately goes narrower still.
--
-- ROLE SCOPE — a real product/policy decision, made conservatively and
-- documented here rather than silently assumed: this platform's locked
-- role list (src/features/auth/types/auth.types.ts) has no "designated
-- safeguarding lead"/"counsellor" role, unlike the real-world practice at
-- most schools of naming one specific accountable individual for this
-- exact purpose. Absent that role existing, access is restricted to
-- school_owner and principal ONLY — narrower than behaviour_incidents
-- (which also includes vice_principal/department_head) and narrower than
-- medical (which also includes medical_officer). This is a deliberately
-- conservative default for a first version of a genuinely high-stakes
-- feature, not a claim that it's the right long-term model — widening it
-- to a real designated-safeguarding-lead concept is future work that
-- needs an actual policy decision, not an engineering judgment call.
--
-- NO GUARDIAN ACCESS AT ALL, unlike behaviour_incidents' guardian_visible
-- flag — there is no policy, RPC, or column anywhere in this migration
-- that a guardian could ever reach. This is deliberate and permanent for
-- this domain, not a "not built yet" gap.
--
-- AUDIT TRAIL: every create and every status change is written to
-- audit_log (FND-ARCH-001, the documented soft-dependency this ticket
-- waited on) via a SECURITY DEFINER trigger — accountability for who
-- touched a safeguarding record and when, matching this domain's stakes.
-- This is an action log (create/status-change), not a per-SELECT access
-- log — no table in this schema logs plain reads, and this migration
-- does not introduce a new pattern for that.
--
-- category is free text, same "no taxonomy exists to defer to" treatment
-- behaviour_incidents.category already established — presuming a specific
-- safeguarding-categories framework (physical/emotional/neglect/online
-- safety/etc.) without an actual policy/legal decision behind it would be
-- inventing product scope this ticket doesn't have the authority to set.

create type public.safeguarding_severity as enum ('low', 'medium', 'high', 'critical');

create type public.safeguarding_status as enum ('open', 'under_review', 'escalated', 'resolved', 'closed');

create table public.safeguarding_concerns (
  id                  uuid primary key default gen_random_uuid(),
  school_id           uuid not null references public.schools (id) on delete cascade,
  learner_id          uuid not null references public.learners (id) on delete cascade,
  category            text,
  description         text not null check (char_length(description) > 0),
  severity            public.safeguarding_severity not null default 'medium',
  status              public.safeguarding_status not null default 'open',
  action_taken        text,
  confidential_notes  text,
  resolved_at         timestamptz,
  created_by          uuid references public.profiles (id) on delete set null,
  updated_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.safeguarding_concerns is 'A recorded child-safeguarding concern and its case status. Restricted to school_owner/principal only (see migration header) — never visible to a guardian, and not surfaced through any general learner-alert or behaviour view. Never hard-deleted — no DELETE policy, same as every other table in this schema. Every create/status-change is written to audit_log by safeguarding_concerns_audit_trigger.';
comment on column public.safeguarding_concerns.confidential_notes is 'Ongoing case notes — the most sensitive field on this table. Same access model as every other column here (no finer-grained column-level restriction exists within this already-narrow role set).';
comment on column public.safeguarding_concerns.resolved_at is 'Server-derived whenever status transitions to/from resolved or closed — never trusted from the client, same pattern as academic_interventions.resolved_at.';

create index safeguarding_concerns_school_id_idx on public.safeguarding_concerns (school_id);
create index safeguarding_concerns_learner_id_idx on public.safeguarding_concerns (learner_id);
create index safeguarding_concerns_status_idx on public.safeguarding_concerns (status);

create trigger safeguarding_concerns_set_updated_at
  before update on public.safeguarding_concerns
  for each row
  execute function public.set_updated_at();

create trigger safeguarding_concerns_set_created_updated_by
  before insert or update on public.safeguarding_concerns
  for each row
  execute function public.set_created_updated_by();

create or replace function public.safeguarding_concerns_validate_tenant()
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
  return new;
end;
$$;

create trigger safeguarding_concerns_validate_tenant_trigger
  before insert or update on public.safeguarding_concerns
  for each row
  execute function public.safeguarding_concerns_validate_tenant();

-- Server-derives resolved_at from status — never trusted from the client,
-- same "server is the source of truth for a derived timestamp" pattern as
-- academic_interventions_sync_resolved_at().
create or replace function public.safeguarding_concerns_sync_resolved_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status in ('resolved', 'closed') and (tg_op = 'INSERT' or old.status not in ('resolved', 'closed')) then
    new.resolved_at := now();
  elsif new.status not in ('resolved', 'closed') then
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

create trigger safeguarding_concerns_sync_resolved_at_trigger
  before insert or update on public.safeguarding_concerns
  for each row
  execute function public.safeguarding_concerns_sync_resolved_at();

-- Audit trail: every create, and every status change, is written to
-- audit_log — accountability for a domain this sensitive.
create or replace function public.safeguarding_concerns_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit_log(
      new.school_id, auth.uid(), 'safeguarding_concern_created', 'safeguarding_concerns', new.id,
      null, jsonb_build_object('learner_id', new.learner_id, 'severity', new.severity, 'status', new.status)
    );
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    perform public.write_audit_log(
      new.school_id, auth.uid(), 'safeguarding_concern_status_changed', 'safeguarding_concerns', new.id,
      jsonb_build_object('status', old.status), jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end;
$$;

create trigger safeguarding_concerns_audit_trigger
  after insert or update on public.safeguarding_concerns
  for each row
  execute function public.safeguarding_concerns_audit();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.safeguarding_concerns enable row level security;
alter table public.safeguarding_concerns force row level security;

create or replace function public.can_view_safeguarding(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_safeguarding(uuid) is
  'Mirrors the app-level learner.view_safeguarding permission (school_owner/principal only — ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts), deliberately narrower than can_view_behaviour()/can_view_learner_medical(). See the migration header''s ROLE SCOPE note. Keep in sync manually.';

create or replace function public.can_manage_safeguarding(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select public.can_view_safeguarding(target_school_id)
$$;

comment on function public.can_manage_safeguarding(uuid) is
  'Currently identical to can_view_safeguarding() — this is the one domain in this schema with no "views but doesn''t manage" tier at all, by design (see migration header).';

grant execute on function public.can_view_safeguarding(uuid) to authenticated;
grant execute on function public.can_manage_safeguarding(uuid) to authenticated;

create policy safeguarding_concerns_select on public.safeguarding_concerns
  for select to authenticated using (public.can_view_safeguarding(school_id));
create policy safeguarding_concerns_insert on public.safeguarding_concerns
  for insert to authenticated with check (public.can_manage_safeguarding(school_id));
create policy safeguarding_concerns_update on public.safeguarding_concerns
  for update to authenticated using (public.can_manage_safeguarding(school_id)) with check (public.can_manage_safeguarding(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete
-- is impossible for any authenticated caller.
