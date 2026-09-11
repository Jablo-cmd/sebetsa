-- Sprint 2 Milestone 1 — Academic Structure
--
-- Five tenant-scoped tables (academic_years, terms, grades, classes,
-- subjects). Field names follow the brief's literal list verbatim,
-- including `school_id` rather than `tenant_id` — this is the same
-- documented precedent as Milestone 5's `profiles.tenant_id`/`profiles.id`
-- reuse (see that migration's header comment and handbook §19): a brief's
-- literal field name is used verbatim for genuinely new columns, without
-- renaming any existing concept. `school_id` here is a new column on a new
-- table, not a rename of anything — it references `public.schools(id)`,
-- exactly like `profiles.tenant_id` does, and is read by RLS via
-- `public.current_tenant_id()` exactly the same way.
--
-- Access model (brief): School Administrator (school_owner) = full access,
-- Principal = manage, Teacher = read-only, everyone else = none. This is
-- narrower than `school.view`/`school.manage` (which most staff roles
-- carry) — deliberately so, per the brief's explicit "no access unless
-- explicitly permitted." `class_teacher`/`subject_teacher` are extended
-- alongside `teacher` for read access, matching the fact that all three
-- already carry an identical framework-level permission set in
-- ROLE_PERMISSIONS (`['school.view']`) — this keeps that existing grouping
-- consistent rather than introducing a special case for academic access
-- alone.

-- ---------------------------------------------------------------------------
-- academic_years

create table public.academic_years (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references public.schools (id) on delete cascade,
  name        text not null check (char_length(name) > 0),
  start_date  date not null,
  end_date    date not null,
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint academic_years_dates_valid check (end_date > start_date)
);

comment on table public.academic_years is 'One row per school per academic year. Tenant-scoped via school_id, mirroring profiles.tenant_id (see migration header).';

create index academic_years_school_id_idx on public.academic_years (school_id);

-- The one-active-year-per-school rule, enforced as a partial unique index
-- (never in application code) — a naive two-step client UPDATE would
-- transiently violate this under concurrent requests, which is exactly why
-- set_active_academic_year() below does both halves of the switch in one
-- transaction instead of leaving it to the client.
create unique index academic_years_one_active_per_school
  on public.academic_years (school_id)
  where is_active;

-- "Unique names where appropriate" (brief, VALIDATION) — case-insensitive,
-- same pattern as profiles_email_key.
create unique index academic_years_school_id_name_key
  on public.academic_years (school_id, lower(name));

create trigger academic_years_set_updated_at
  before update on public.academic_years
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- terms

-- `active` is not in the brief's literal field list for terms, unlike
-- grades/classes/subjects — but the brief's ARCHIVE RULE section states
-- unconditionally that "academic entities are never hard deleted," and
-- terms is an academic entity with no other archive mechanism available.
-- Per the established resolution pattern for a brief's literal field list
-- conflicting with an explicit requirement (handbook rule #14 / the M5
-- migration precedent): this is a genuinely new column needed to satisfy
-- an explicit, higher-level rule, not a guess — added for consistency
-- with grades.active/classes.active/subjects.active rather than silently
-- allowing terms to be the one entity that can be hard-deleted.
create table public.terms (
  id                uuid primary key default gen_random_uuid(),
  academic_year_id  uuid not null references public.academic_years (id) on delete cascade,
  school_id         uuid not null references public.schools (id) on delete cascade,
  name              text not null check (char_length(name) > 0),
  sequence          integer not null check (sequence > 0),
  start_date        date not null,
  end_date          date not null,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint terms_dates_valid check (end_date > start_date)
);

comment on table public.terms is 'Terms within an academic year. Carries school_id directly (denormalized from academic_years.school_id) so RLS does not need a join — see terms_validate_academic_year_school() for why that denormalization is safe. Never hard-deleted — active=false is the archive state (see migration header note on this column).';
comment on column public.terms.school_id is 'Must equal the referenced academic_years.school_id — enforced by terms_validate_academic_year_school(), since a foreign key alone does not check this and does not respect RLS (a client could otherwise reference another tenant''s academic_year_id despite never being able to SELECT it).';

create index terms_academic_year_id_idx on public.terms (academic_year_id);
create index terms_school_id_idx on public.terms (school_id);
create unique index terms_academic_year_id_name_key on public.terms (academic_year_id, lower(name));
create unique index terms_academic_year_id_sequence_key on public.terms (academic_year_id, sequence);

create trigger terms_set_updated_at
  before update on public.terms
  for each row
  execute function public.set_updated_at();

-- Closes the FK-doesn't-respect-RLS gap: a foreign key only checks that the
-- referenced row exists, not that the caller could ever SELECT it under
-- RLS, so without this a client could set school_id to their own tenant
-- while pointing academic_year_id at a different tenant's row (guessed or
-- leaked UUID), corrupting the term's effective tenant scoping.
create or replace function public.terms_validate_academic_year_school()
returns trigger
language plpgsql
as $$
declare
  v_year_school_id uuid;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: terms.school_id must match the referenced academic_years.school_id';
  end if;
  return new;
end;
$$;

create trigger terms_validate_academic_year_school_trigger
  before insert or update on public.terms
  for each row
  execute function public.terms_validate_academic_year_school();

-- ---------------------------------------------------------------------------
-- grades

create table public.grades (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  name         text not null check (char_length(name) > 0),
  code         text,
  description  text,
  sort_order   integer not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.grades is 'A school''s grade catalogue (e.g. Grade R, Grade 1 .. Grade 12). Never hard-deleted — active=false is the archive state.';

create index grades_school_id_idx on public.grades (school_id);
create index grades_school_id_sort_order_idx on public.grades (school_id, sort_order);
create unique index grades_school_id_name_key on public.grades (school_id, lower(name));

create trigger grades_set_updated_at
  before update on public.grades
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- classes

create table public.classes (
  id          uuid primary key default gen_random_uuid(),
  grade_id    uuid not null references public.grades (id) on delete cascade,
  school_id   uuid not null references public.schools (id) on delete cascade,
  name        text not null check (char_length(name) > 0),
  capacity    integer not null check (capacity > 0),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.classes is 'A class/section within a grade (e.g. Grade 8A). Never hard-deleted — active=false is the archive state.';
comment on column public.classes.school_id is 'Must equal the referenced grades.school_id — enforced by classes_validate_grade_school(), same reasoning as terms_validate_academic_year_school().';

create index classes_grade_id_idx on public.classes (grade_id);
create index classes_school_id_idx on public.classes (school_id);
create unique index classes_school_id_name_key on public.classes (school_id, lower(name));

create trigger classes_set_updated_at
  before update on public.classes
  for each row
  execute function public.set_updated_at();

create or replace function public.classes_validate_grade_school()
returns trigger
language plpgsql
as $$
declare
  v_grade_school_id uuid;
begin
  select school_id into v_grade_school_id from public.grades where id = new.grade_id;
  if v_grade_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: classes.school_id must match the referenced grades.school_id';
  end if;
  return new;
end;
$$;

create trigger classes_validate_grade_school_trigger
  before insert or update on public.classes
  for each row
  execute function public.classes_validate_grade_school();

-- ---------------------------------------------------------------------------
-- subjects

create table public.subjects (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  name         text not null check (char_length(name) > 0),
  code         text,
  description  text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.subjects is 'A school''s subject catalogue (e.g. Mathematics, English). Never hard-deleted — active=false is the archive state.';

create index subjects_school_id_idx on public.subjects (school_id);
create unique index subjects_school_id_name_key on public.subjects (school_id, lower(name));

create trigger subjects_set_updated_at
  before update on public.subjects
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS: enable + force on all five tables, exactly the standard pattern
-- (handbook §8), gated by two new authorization functions below rather
-- than the blanket tenant-only pattern schools/profiles use — academic
-- data is role-gated within the tenant too (brief: Teacher is read-only,
-- most other roles get no access at all), so SELECT itself must check role,
-- not just school_id.

alter table public.academic_years enable row level security;
alter table public.academic_years force row level security;
alter table public.terms enable row level security;
alter table public.terms force row level security;
alter table public.grades enable row level security;
alter table public.grades force row level security;
alter table public.classes enable row level security;
alter table public.classes force row level security;
alter table public.subjects enable row level security;
alter table public.subjects force row level security;

-- Mirrors the app-level `academic.view` permission (see
-- src/features/rbac/constants/rolePermissions.ts) — school_owner,
-- principal, and all three teacher-variant roles (teacher, class_teacher,
-- subject_teacher — grouped together because they already carry an
-- identical framework-level permission set, see migration header), or any
-- platform admin. Keep both in sync manually — SQL cannot introspect the
-- TS Permission union.
create or replace function public.can_view_academic(target_school_id uuid)
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

comment on function public.can_view_academic(uuid) is
  'Mirrors the app-level academic.view permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- Mirrors the app-level `academic.manage` permission — school_owner and
-- principal only (brief: "School Administrator: Full access. Principal:
-- Manage academic structure."), or any platform admin. Same shape as
-- can_manage_school().
create or replace function public.can_manage_academic(target_school_id uuid)
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

comment on function public.can_manage_academic(uuid) is
  'Mirrors the app-level academic.manage permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

grant execute on function public.can_view_academic(uuid) to authenticated;
grant execute on function public.can_manage_academic(uuid) to authenticated;

-- One SELECT/INSERT/UPDATE policy set per table, all built on the two
-- functions above. No DELETE policy is defined for any of the five tables
-- — combined with FORCE ROW LEVEL SECURITY, this means no authenticated
-- client can ever hard-delete an academic record, which is exactly the
-- brief's archive-only rule ("Academic entities are NEVER hard deleted")
-- enforced at the database layer, not just left to UI convention.

create policy academic_years_select on public.academic_years
  for select to authenticated using (public.can_view_academic(school_id));
create policy academic_years_insert on public.academic_years
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy academic_years_update on public.academic_years
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

create policy terms_select on public.terms
  for select to authenticated using (public.can_view_academic(school_id));
create policy terms_insert on public.terms
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy terms_update on public.terms
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

create policy grades_select on public.grades
  for select to authenticated using (public.can_view_academic(school_id));
create policy grades_insert on public.grades
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy grades_update on public.grades
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

create policy classes_select on public.classes
  for select to authenticated using (public.can_view_academic(school_id));
create policy classes_insert on public.classes
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy classes_update on public.classes
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

create policy subjects_select on public.subjects
  for select to authenticated using (public.can_view_academic(school_id));
create policy subjects_insert on public.subjects
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy subjects_update on public.subjects
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

-- ---------------------------------------------------------------------------
-- Activation guard: direct client UPDATEs may archive an academic year
-- (set is_active false) freely under the policy above, but may NOT
-- directly flip is_active to true — only set_active_academic_year() may,
-- via the same transaction-local set_config() flag pattern already
-- established for profiles.role/profiles.tenant_id (see
-- 20260802151501_user_role_management.sql and
-- 20260803140000_prevent_direct_tenant_change.sql). This is what keeps
-- "Archive" (ordinary UPDATE, is_active -> false) and "Activate" (must go
-- through the atomic RPC) as genuinely distinct operations, and is what
-- makes the one-active-year guarantee race-free even against a client that
-- tries to bypass the RPC.
create or replace function public.prevent_direct_year_activation()
returns trigger
language plpgsql
as $$
begin
  if new.is_active and not old.is_active and coalesce(current_setting('app.allow_year_activation', true), '') <> 'true' then
    raise exception 'insufficient_privilege: an academic year can only be activated via set_active_academic_year()';
  end if;
  return new;
end;
$$;

create trigger academic_years_prevent_direct_activation
  before update on public.academic_years
  for each row
  execute function public.prevent_direct_year_activation();

-- set_active_academic_year: deactivates whichever year is currently active
-- for the school (if any) and activates the requested one, in one
-- transaction, so the partial unique index is never transiently violated
-- and no concurrent caller can observe (or cause) two simultaneously
-- active years. can_manage_academic() is checked explicitly inside the
-- function body — not merely relied upon via RLS on the table — following
-- the same defense-in-depth pattern as admin_create_user's tenant check.
create or replace function public.set_active_academic_year(p_academic_year_id uuid)
returns public.academic_years
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_result public.academic_years;
begin
  select school_id into v_school_id from public.academic_years where id = p_academic_year_id;
  if not found then
    raise exception 'not_found: no academic year %', p_academic_year_id;
  end if;

  if not public.can_manage_academic(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage academic years for this school';
  end if;

  update public.academic_years
    set is_active = false
    where school_id = v_school_id and is_active = true and id <> p_academic_year_id;

  perform set_config('app.allow_year_activation', 'true', true);
  update public.academic_years set is_active = true where id = p_academic_year_id
    returning * into v_result;

  return v_result;
end;
$$;

comment on function public.set_active_academic_year(uuid) is
  'Atomically deactivates the school''s currently active academic year (if any) and activates the requested one. The only path that may set academic_years.is_active = true — see prevent_direct_year_activation().';

grant execute on function public.set_active_academic_year(uuid) to authenticated;
