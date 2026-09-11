-- Behaviour / Discipline Domain
--
-- A single table covering both commendations and disciplinary incidents
-- (incident_type distinguishes them), matching how real school behaviour
-- policy treats them as two sides of the same recorded-event concept rather
-- than separate systems. `category` is free text, not a closed enum — no
-- existing taxonomy exists anywhere in this schema to defer to, and school
-- behaviour category lists vary too widely to invent one; this is the same
-- treatment already given to learners.gender/transport_mode ("explicitly
-- left as open product-policy questions, not given a concrete list").
-- `created_by` (from the shared set_created_updated_by trigger) is the
-- "staff member who recorded it" — no separate column needed.
--
-- RBAC: vice_principal and department_head already existed as roles with
-- zero permissions beyond school.view — reserved, per rolePermissions.ts's
-- own shape, for exactly this domain. Unlike medical/financial, there is no
-- "views but doesn't manage" role here (no equivalent narrow specialist
-- role exists for discipline), so view and manage share the same role set.
--
-- SECURITY DEFINER — applied precisely, per the assessments migration's own
-- documented lesson, not reflexively: behaviour_incidents_validate_tenant()
-- reads `learners`, gated by can_view_learners() — which vice_principal/
-- department_head do NOT hold. Needs SECURITY DEFINER, or every incident
-- they record fails silently. can_view_behaviour()/can_manage_behaviour()
-- only check role + current_tenant_id() (itself SECURITY DEFINER) — no
-- other gated table read, so plain SECURITY INVOKER is correct, exactly
-- mirroring can_view_learner_medical()'s own shape.

create type public.behaviour_incident_type as enum ('positive', 'negative');

create type public.behaviour_severity as enum ('low', 'medium', 'high');

create table public.behaviour_incidents (
  id                   uuid primary key default gen_random_uuid(),
  school_id            uuid not null references public.schools (id) on delete cascade,
  learner_id           uuid not null references public.learners (id) on delete cascade,
  academic_year_id     uuid not null references public.academic_years (id),
  incident_type        public.behaviour_incident_type not null,
  severity             public.behaviour_severity,
  category             text,
  occurred_at          timestamptz not null default now(),
  description          text not null check (char_length(description) > 0),
  action_taken         text,
  outcome              text,
  follow_up_required   boolean not null default false,
  follow_up_notes      text,
  active               boolean not null default true,
  created_by           uuid references public.profiles (id) on delete set null,
  updated_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.behaviour_incidents is 'Both positive (commendation) and negative (disciplinary) behaviour records for a learner — incident_type distinguishes them. severity is meaningful only for negative incidents (nullable). Never hard-deleted — active=false is the archive state, same pattern as every other table in this schema. created_by (set by the shared trigger) is the staff member who recorded it.';
comment on column public.behaviour_incidents.category is 'Free text — no behaviour-category taxonomy exists anywhere in this schema to defer to; same treatment as learners.gender/transport_mode.';
comment on column public.behaviour_incidents.severity is 'NULL for positive incidents; typically set for negative ones.';

create index behaviour_incidents_school_id_idx on public.behaviour_incidents (school_id);
create index behaviour_incidents_learner_id_idx on public.behaviour_incidents (learner_id);
create index behaviour_incidents_academic_year_id_idx on public.behaviour_incidents (academic_year_id);
create index behaviour_incidents_occurred_at_idx on public.behaviour_incidents (occurred_at);

create trigger behaviour_incidents_set_updated_at
  before update on public.behaviour_incidents
  for each row
  execute function public.set_updated_at();

create trigger behaviour_incidents_set_created_updated_by
  before insert or update on public.behaviour_incidents
  for each row
  execute function public.set_created_updated_by();

create or replace function public.behaviour_incidents_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger behaviour_incidents_validate_tenant_trigger
  before insert or update on public.behaviour_incidents
  for each row
  execute function public.behaviour_incidents_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.behaviour_incidents enable row level security;
alter table public.behaviour_incidents force row level security;

-- Mirrors the app-level learner.view_behaviour permission — school_owner,
-- principal, vice_principal, department_head, or any platform admin.
create or replace function public.can_view_behaviour(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'vice_principal', 'department_head')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_behaviour(uuid) is
  'Mirrors the app-level learner.view_behaviour permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- Mirrors the app-level learner.manage_behaviour permission. Same role set
-- as view — unlike medical/financial, there is no narrower specialist role
-- for discipline that views without managing.
create or replace function public.can_manage_behaviour(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select public.can_view_behaviour(target_school_id)
$$;

comment on function public.can_manage_behaviour(uuid) is
  'Mirrors the app-level learner.manage_behaviour permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Currently identical to can_view_behaviour() — kept as a separate function so the two permissions can diverge later without an RLS rewrite. Keep in sync manually.';

grant execute on function public.can_view_behaviour(uuid) to authenticated;
grant execute on function public.can_manage_behaviour(uuid) to authenticated;

create policy behaviour_incidents_select on public.behaviour_incidents
  for select to authenticated using (public.can_view_behaviour(school_id));
create policy behaviour_incidents_insert on public.behaviour_incidents
  for insert to authenticated with check (public.can_manage_behaviour(school_id));
create policy behaviour_incidents_update on public.behaviour_incidents
  for update to authenticated using (public.can_manage_behaviour(school_id)) with check (public.can_manage_behaviour(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete is
-- impossible for any authenticated caller, same as every other table in
-- this schema.
