-- FND-ACA-006: Academic intervention tracking — a real, persisted workflow
-- ("this learner needs extra support in Mathematics, assigned to Ms. X,
-- reviewed by end of term") beyond src/features/learners/utils/
-- learnerAlerts.ts's existing free-text alert derivation, which is
-- entirely transient: it recomputes a banner from already-fetched data on
-- every page load, with no way to acknowledge it, assign an owner, or
-- record that something was actually done about it. This table is that
-- durable half — deliberately NOT a replacement for the alert banner
-- (which stays exactly as useful a "something needs attention" nudge as
-- before), just the thing a member of staff can act on to actually follow
-- up, matching the shape behaviour_incidents already established for a
-- conceptually adjacent "recorded event about a learner" table.
--
-- RBAC: new can_view_academic_intervention()/can_manage_academic_
-- intervention() helpers, deliberately mirroring assessment.manage's own
-- role set (school_owner, principal, teacher, class_teacher,
-- subject_teacher) rather than inventing a new permission — an academic
-- intervention is conceptually adjacent to assessment results (both are
-- about a learner's academic standing) and the same "who teaches/leads"
-- role set applies to acting on either. Unlike can_manage_assessment()'s
-- own per-class-teaching-assignment scoping, this stays school-wide (no
-- target_class_id) — same simplification behaviour_incidents already made
-- for the same reason: keeping the RLS check itself simple was judged more
-- valuable here than narrowing to "only the learner's own teacher", and a
-- school can revisit that narrowing later without a schema change.
--
-- SECURITY DEFINER on the tenant-validation trigger — same reasoning as
-- behaviour_incidents_validate_tenant(): it reads learners/academic_years/
-- subjects, gated by can_view_learners()/can_view_academic() which
-- teacher/class_teacher/subject_teacher do not hold.

create type public.academic_intervention_status as enum ('open', 'in_progress', 'resolved');

create table public.academic_interventions (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools (id) on delete cascade,
  learner_id         uuid not null references public.learners (id) on delete cascade,
  academic_year_id   uuid not null references public.academic_years (id),
  subject_id         uuid references public.subjects (id),
  title              text not null check (char_length(title) > 0),
  description        text,
  status             public.academic_intervention_status not null default 'open',
  target_date        date,
  resolved_at        timestamptz,
  resolution_notes   text,
  created_by         uuid references public.profiles (id) on delete set null,
  updated_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.academic_interventions is 'A persisted, actionable academic support record for a learner — status-tracked (open/in_progress/resolved), unlike the transient alert banner derived in learnerAlerts.ts. Never hard-deleted — no DELETE policy, same pattern as every other table in this schema; a record entered in error is a data-correction concern for a platform admin, not a normal staff action.';
comment on column public.academic_interventions.subject_id is 'Optional — set when the intervention is scoped to one subject (e.g. "extra Mathematics support"); null for a general/cross-subject concern.';
comment on column public.academic_interventions.resolved_at is 'Set automatically by academic_interventions_sync_resolved_at() whenever status transitions to/from resolved — never set directly by a client write.';

create index academic_interventions_school_id_idx on public.academic_interventions (school_id);
create index academic_interventions_learner_id_idx on public.academic_interventions (learner_id);
create index academic_interventions_academic_year_id_idx on public.academic_interventions (academic_year_id);
create index academic_interventions_status_idx on public.academic_interventions (status);

create trigger academic_interventions_set_updated_at
  before update on public.academic_interventions
  for each row
  execute function public.set_updated_at();

create trigger academic_interventions_set_created_updated_by
  before insert or update on public.academic_interventions
  for each row
  execute function public.set_created_updated_by();

-- Keeps resolved_at in lockstep with status server-side, regardless of what
-- a client sends for that column — mirrors the same "server is the source
-- of truth for a derived timestamp" reasoning as notifications.read_at
-- (set once, by the recipient reading it) rather than trusting every
-- caller to compute it correctly.
create or replace function public.academic_interventions_sync_resolved_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'resolved' and (tg_op = 'INSERT' or old.status is distinct from 'resolved') then
    new.resolved_at := now();
  elsif new.status is distinct from 'resolved' then
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

create trigger academic_interventions_sync_resolved_at_trigger
  before insert or update on public.academic_interventions
  for each row
  execute function public.academic_interventions_sync_resolved_at();

create or replace function public.academic_interventions_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
  v_subject_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  if new.subject_id is not null then
    select school_id into v_subject_school_id from public.subjects where id = new.subject_id;
    if v_subject_school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: subject_id must belong to the same school';
    end if;
  end if;

  return new;
end;
$$;

create trigger academic_interventions_validate_tenant_trigger
  before insert or update on public.academic_interventions
  for each row
  execute function public.academic_interventions_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.academic_interventions enable row level security;
alter table public.academic_interventions force row level security;

create or replace function public.can_view_academic_intervention(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'teacher', 'class_teacher', 'subject_teacher')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_academic_intervention(uuid) is
  'Mirrors assessment.manage''s own role set (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts) — an academic intervention is conceptually adjacent to assessment results, not a new permission. Keep in sync manually.';

create or replace function public.can_manage_academic_intervention(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select public.can_view_academic_intervention(target_school_id)
$$;

comment on function public.can_manage_academic_intervention(uuid) is
  'Currently identical to can_view_academic_intervention() — kept as a separate function so the two can diverge later without an RLS rewrite, same pattern as can_manage_behaviour().';

grant execute on function public.can_view_academic_intervention(uuid) to authenticated;
grant execute on function public.can_manage_academic_intervention(uuid) to authenticated;

create policy academic_interventions_select on public.academic_interventions
  for select to authenticated using (public.can_view_academic_intervention(school_id));
create policy academic_interventions_insert on public.academic_interventions
  for insert to authenticated with check (public.can_manage_academic_intervention(school_id));
create policy academic_interventions_update on public.academic_interventions
  for update to authenticated using (public.can_manage_academic_intervention(school_id)) with check (public.can_manage_academic_intervention(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete is
-- impossible for any authenticated caller, same as every other table in
-- this schema.
