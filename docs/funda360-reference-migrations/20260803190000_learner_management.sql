-- Sprint 2 Milestone 3 — Learner Management (Phase 1: Database)
--
-- Six tenant-scoped tables. learners is the Student Information System (SIS)
-- master record — a third domain alongside profiles (auth/authz) and
-- employees (HR), following the exact same boundary: profile_id is
-- optional (most learners will never have a login), ON DELETE SET NULL
-- (never CASCADE — the SIS record must survive account deletion), and
-- learners owns first_name/last_name/preferred_name unconditionally.
-- profiles is never read or written by this migration's triggers.
--
-- Per the locked architecture correction pass: no `houses` table (no
-- repository evidence supported one — `house` is a free-text field on
-- learner_enrollments, the same treatment as `stream`) and no `religion`
-- field (no documented requirement anywhere in the repository).
--
-- gender and transport_mode are plain nullable text, not enums — their
-- value sets were explicitly left as open product-policy questions in the
-- locked architecture, not given a concrete list. Encoding an invented
-- value set into an enum type would be introducing something not approved.

-- ---------------------------------------------------------------------------
-- enums (only where the locked architecture gave an explicit value list)

create type public.learner_status as enum (
  'prospective', 'applied', 'accepted', 'enrolled', 'active',
  'suspended', 'transferred', 'graduated', 'withdrawn'
);

create type public.boarding_type as enum ('day_scholar', 'boarder');

create type public.learner_enrollment_status as enum (
  'enrolled', 'promoted', 'repeated', 'transferred_out', 'withdrawn'
);

create type public.guardian_relationship_type as enum (
  'mother', 'father', 'legal_guardian', 'grandparent', 'sibling', 'other'
);

create type public.learner_document_type as enum (
  'birth_certificate', 'id_copy', 'passport', 'permit',
  'transfer_letter', 'medical_certificate', 'report_card', 'other'
);

-- ---------------------------------------------------------------------------
-- learners

create table public.learners (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid not null references public.schools (id) on delete cascade,
  profile_id            uuid references public.profiles (id) on delete set null,
  learner_number        text not null check (char_length(learner_number) > 0),
  admission_number      text not null check (char_length(admission_number) > 0),
  first_name            text not null check (char_length(first_name) > 0),
  last_name             text not null check (char_length(last_name) > 0),
  preferred_name        text,
  gender                text,
  date_of_birth         date not null,
  id_number             text,
  passport_number       text,
  passport_country      text,
  nationality           text,
  home_language         text,
  additional_languages  text[],
  photo_url             text,
  transport_mode        text,
  transport_notes       text,
  boarding_type         public.boarding_type,
  status                public.learner_status not null default 'prospective',
  status_reason         text,
  admission_date        date not null,
  created_by            uuid references public.profiles (id) on delete set null,
  updated_by            uuid references public.profiles (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint learners_dob_not_future check (date_of_birth < current_date),
  constraint learners_dob_plausible check (date_of_birth > current_date - interval '25 years')
);

comment on table public.learners is 'The SIS master record. Independent of login status — profile_id is optional, ON DELETE SET NULL. Owns first_name/last_name/preferred_name exclusively; profiles is never read or written by this table or its triggers.';
comment on column public.learners.profile_id is 'Optional link to a login account (e.g. a future student/parent portal). ON DELETE SET NULL, never CASCADE — the SIS record must survive profile deletion.';
comment on column public.learners.admission_number is 'Single permanent value per learner_number-established note in the architecture doc. Whether the application layer ever regenerates this on re-admission is an explicit open product-policy question, not resolved by this schema — the column simply stores whatever value is written.';
comment on column public.learners.status is 'Single lifecycle field — deliberately not four separate admission/enrolment/graduation/withdrawal status columns, per the locked architecture single-source-of-truth decision. Transitions validated by learners_validate_status_transition().';

create index learners_school_id_idx on public.learners (school_id);
create index learners_school_id_status_idx on public.learners (school_id, status);

create unique index learners_school_id_learner_number_key on public.learners (school_id, learner_number);
create unique index learners_school_id_admission_number_key on public.learners (school_id, admission_number);
create unique index learners_school_id_id_number_key on public.learners (school_id, id_number) where id_number is not null;
create unique index learners_profile_id_key on public.learners (profile_id) where profile_id is not null;

create trigger learners_set_updated_at
  before update on public.learners
  for each row
  execute function public.set_updated_at();

create trigger learners_set_created_updated_by
  before insert or update on public.learners
  for each row
  execute function public.set_created_updated_by();

-- Status transition whitelist — fires on any UPDATE that changes status,
-- whether via change_learner_status() or a direct UPDATE from a manager.
-- Unlike academic_years.is_active, there is no cross-row atomicity
-- invariant to protect here (no "only one X" rule), so a hard block on
-- direct writes (the set_config flag pattern) is not required — the
-- trigger's whitelist check alone is sufficient and applies uniformly
-- regardless of path.
create or replace function public.learners_validate_status_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'prospective' and new.status = 'applied') or
    (old.status = 'applied' and new.status in ('accepted', 'withdrawn')) or
    (old.status = 'accepted' and new.status in ('enrolled', 'withdrawn')) or
    (old.status = 'enrolled' and new.status = 'active') or
    (old.status = 'active' and new.status in ('suspended', 'transferred', 'graduated', 'withdrawn')) or
    (old.status = 'suspended' and new.status in ('active', 'withdrawn')) or
    (old.status = 'transferred' and new.status = 'applied') or
    (old.status = 'withdrawn' and new.status = 'applied')
  ) then
    raise exception 'insufficient_privilege: invalid learner status transition from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger learners_validate_status_transition_trigger
  before update on public.learners
  for each row
  execute function public.learners_validate_status_transition();

-- ---------------------------------------------------------------------------
-- learner_enrollments — year-by-year placement history (the mechanism that
-- makes "promotion history" possible; flat current-grade columns on
-- learners would lose it on every promotion).

create table public.learner_enrollments (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools (id) on delete cascade,
  learner_id         uuid not null references public.learners (id) on delete cascade,
  academic_year_id   uuid not null references public.academic_years (id),
  grade_id           uuid not null references public.grades (id),
  class_id           uuid references public.classes (id),
  house              text,
  stream             text,
  enrollment_date    date not null,
  enrollment_status  public.learner_enrollment_status not null default 'enrolled',
  created_by         uuid references public.profiles (id) on delete set null,
  updated_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.learner_enrollments is 'One row per (learner, academic_year) — the placement/promotion history. Mid-year class changes are UPDATEs to the existing row, not new rows. house/stream are free text — no repository evidence supported a houses catalogue table.';

create unique index learner_enrollments_learner_id_academic_year_id_key on public.learner_enrollments (learner_id, academic_year_id);
create index learner_enrollments_school_id_idx on public.learner_enrollments (school_id);
create index learner_enrollments_learner_id_idx on public.learner_enrollments (learner_id);
create index learner_enrollments_academic_year_id_idx on public.learner_enrollments (academic_year_id);
create index learner_enrollments_grade_id_idx on public.learner_enrollments (grade_id);
create index learner_enrollments_class_id_idx on public.learner_enrollments (class_id);

create trigger learner_enrollments_set_updated_at
  before update on public.learner_enrollments
  for each row
  execute function public.set_updated_at();

create trigger learner_enrollments_set_created_updated_by
  before insert or update on public.learner_enrollments
  for each row
  execute function public.set_created_updated_by();

-- Closes the FK-doesn't-respect-RLS gap for every reference this row
-- makes, and enforces grade/class consistency, in one trigger (all checks
-- touch the same row's insert/update).
create or replace function public.learner_enrollments_validate_tenant_and_grade()
returns trigger
language plpgsql
as $$
declare
  v_learner_school_id uuid;
  v_year_school_id uuid;
  v_grade_school_id uuid;
  v_class_school_id uuid;
  v_class_grade_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_enrollments.school_id must match the referenced learner''s school';
  end if;

  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id into v_grade_school_id from public.grades where id = new.grade_id;
  if v_grade_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: grade_id must belong to the same school';
  end if;

  if new.class_id is not null then
    select school_id, grade_id into v_class_school_id, v_class_grade_id from public.classes where id = new.class_id;
    if v_class_school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: class_id must belong to the same school';
    end if;
    if v_class_grade_id is distinct from new.grade_id then
      raise exception 'insufficient_privilege: class_id must belong to the same grade as this enrollment';
    end if;
  end if;

  return new;
end;
$$;

create trigger learner_enrollments_validate_tenant_and_grade_trigger
  before insert or update on public.learner_enrollments
  for each row
  execute function public.learner_enrollments_validate_tenant_and_grade();

-- ---------------------------------------------------------------------------
-- learner_guardians — relationship to EXISTING profiles (role=parent/
-- guardian). The Guardian module itself is out of scope; this only adds
-- the join.

create table public.learner_guardians (
  id                   uuid primary key default gen_random_uuid(),
  school_id            uuid not null references public.schools (id) on delete cascade,
  learner_id           uuid not null references public.learners (id) on delete cascade,
  guardian_profile_id  uuid not null references public.profiles (id) on delete cascade,
  relationship_type    public.guardian_relationship_type not null,
  is_primary           boolean not null default false,
  custody_notes        text,
  created_by           uuid references public.profiles (id) on delete set null,
  updated_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.learner_guardians is 'Relationship join between learners and existing profiles (role=parent/guardian) — not a new Guardian entity. guardian_profile_id is ON DELETE CASCADE (unlike learners.profile_id): if the guardian account is deleted, the relationship row itself has no remaining purpose.';

create unique index learner_guardians_learner_id_guardian_profile_id_key on public.learner_guardians (learner_id, guardian_profile_id);
create unique index learner_guardians_one_primary_per_learner on public.learner_guardians (learner_id) where is_primary;
create index learner_guardians_school_id_idx on public.learner_guardians (school_id);
create index learner_guardians_learner_id_idx on public.learner_guardians (learner_id);
create index learner_guardians_guardian_profile_id_idx on public.learner_guardians (guardian_profile_id);

create trigger learner_guardians_set_updated_at
  before update on public.learner_guardians
  for each row
  execute function public.set_updated_at();

create trigger learner_guardians_set_created_updated_by
  before insert or update on public.learner_guardians
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_guardians_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_learner_school_id uuid;
  v_guardian_tenant_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_guardians.school_id must match the referenced learner''s school';
  end if;

  select tenant_id into v_guardian_tenant_id from public.profiles where id = new.guardian_profile_id;
  if v_guardian_tenant_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: guardian_profile_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger learner_guardians_validate_tenant_trigger
  before insert or update on public.learner_guardians
  for each row
  execute function public.learner_guardians_validate_tenant();

-- ---------------------------------------------------------------------------
-- learner_emergency_contacts — deliberately NOT linked to profiles (no
-- login, no legal relationship implied — distinct from learner_guardians).

create table public.learner_emergency_contacts (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  learner_id        uuid not null references public.learners (id) on delete cascade,
  name              text not null check (char_length(name) > 0),
  relationship      text,
  phone             text not null check (char_length(phone) > 0),
  alternate_phone   text,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index learner_emergency_contacts_school_id_idx on public.learner_emergency_contacts (school_id);
create index learner_emergency_contacts_learner_id_idx on public.learner_emergency_contacts (learner_id);

create trigger learner_emergency_contacts_set_updated_at
  before update on public.learner_emergency_contacts
  for each row
  execute function public.set_updated_at();

create trigger learner_emergency_contacts_set_created_updated_by
  before insert or update on public.learner_emergency_contacts
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_emergency_contacts_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_learner_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_emergency_contacts.school_id must match the referenced learner''s school';
  end if;
  return new;
end;
$$;

create trigger learner_emergency_contacts_validate_tenant_trigger
  before insert or update on public.learner_emergency_contacts
  for each row
  execute function public.learner_emergency_contacts_validate_tenant();

-- ---------------------------------------------------------------------------
-- learner_medical_information — 1:1, separately RLS-gated (see
-- can_view_learner_medical/can_manage_learner_medical below). A real
-- database-level protection, not an application-layer-only convention —
-- corrects the weaker pattern Employee Management's employee.view_sensitive
-- left as a known gap.

create table public.learner_medical_information (
  id                        uuid primary key default gen_random_uuid(),
  school_id                 uuid not null references public.schools (id) on delete cascade,
  learner_id                uuid not null references public.learners (id) on delete cascade,
  allergies                 text,
  medication                text,
  medical_conditions        text,
  doctor_name               text,
  doctor_phone              text,
  medical_aid_provider      text,
  medical_aid_number        text,
  emergency_medical_notes   text,
  created_by                uuid references public.profiles (id) on delete set null,
  updated_by                uuid references public.profiles (id) on delete set null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create unique index learner_medical_information_learner_id_key on public.learner_medical_information (learner_id);
create index learner_medical_information_school_id_idx on public.learner_medical_information (school_id);

create trigger learner_medical_information_set_updated_at
  before update on public.learner_medical_information
  for each row
  execute function public.set_updated_at();

create trigger learner_medical_information_set_created_updated_by
  before insert or update on public.learner_medical_information
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_medical_information_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_learner_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_medical_information.school_id must match the referenced learner''s school';
  end if;
  return new;
end;
$$;

create trigger learner_medical_information_validate_tenant_trigger
  before insert or update on public.learner_medical_information
  for each row
  execute function public.learner_medical_information_validate_tenant();

-- ---------------------------------------------------------------------------
-- learner_documents — metadata only. The actual file-upload mechanism is a
-- pre-existing, cross-cutting platform gap (no Storage wiring exists
-- anywhere yet); this table does not depend on it existing.

create table public.learner_documents (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references public.schools (id) on delete cascade,
  learner_id     uuid not null references public.learners (id) on delete cascade,
  document_type  public.learner_document_type not null,
  file_url       text not null check (char_length(file_url) > 0),
  file_name      text,
  uploaded_at    timestamptz not null default now(),
  notes          text,
  active         boolean not null default true,
  created_by     uuid references public.profiles (id) on delete set null,
  updated_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.learner_documents is 'Metadata only — never hard-deleted, active=false is the archive state. file_url assumes Supabase Storage wiring this codebase has not yet built (same pre-existing gap as schools.logo_url/profiles.avatar_url).';

create index learner_documents_school_id_idx on public.learner_documents (school_id);
create index learner_documents_learner_id_idx on public.learner_documents (learner_id);

create trigger learner_documents_set_updated_at
  before update on public.learner_documents
  for each row
  execute function public.set_updated_at();

create trigger learner_documents_set_created_updated_by
  before insert or update on public.learner_documents
  for each row
  execute function public.set_created_updated_by();

create or replace function public.learner_documents_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_learner_school_id uuid;
begin
  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_documents.school_id must match the referenced learner''s school';
  end if;
  return new;
end;
$$;

create trigger learner_documents_validate_tenant_trigger
  before insert or update on public.learner_documents
  for each row
  execute function public.learner_documents_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.learners enable row level security;
alter table public.learners force row level security;
alter table public.learner_enrollments enable row level security;
alter table public.learner_enrollments force row level security;
alter table public.learner_guardians enable row level security;
alter table public.learner_guardians force row level security;
alter table public.learner_emergency_contacts enable row level security;
alter table public.learner_emergency_contacts force row level security;
alter table public.learner_medical_information enable row level security;
alter table public.learner_medical_information force row level security;
alter table public.learner_documents enable row level security;
alter table public.learner_documents force row level security;

-- Mirrors the app-level learner.view permission (ROLE_PERMISSIONS in
-- src/features/rbac/constants/rolePermissions.ts) — school_owner,
-- principal, admissions_officer, medical_officer (needs the general
-- directory to identify which learner they're viewing medical info for),
-- or any platform admin. Keep in sync manually.
create or replace function public.can_view_learners(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'admissions_officer', 'medical_officer')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_learners(uuid) is
  'Mirrors the app-level learner.view permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- Mirrors the app-level learner.manage permission — school_owner,
-- principal, admissions_officer, or any platform admin. Note: the locked
-- architecture's access matrix scopes Admissions Officer's manage rights
-- to "prospective through enrolled" stages, but specifies no concrete
-- mechanism for that restriction — no stage-conditional logic exists
-- anywhere else in this schema to model it on, so this grants full manage
-- at the database layer; stage-scoping (if still wanted) is an
-- application-layer concern for a later phase, consistent with "do not
-- move application validation into the database unless explicitly
-- required."
create or replace function public.can_manage_learners(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal', 'admissions_officer')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_learners(uuid) is
  'Mirrors the app-level learner.manage permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- Mirrors the app-level learner.view_medical permission — school_owner,
-- principal (duty-of-care exception, see architecture doc §4), or
-- medical_officer, or any platform admin.
create or replace function public.can_view_learner_medical(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal', 'medical_officer')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_learner_medical(uuid) is
  'Mirrors the app-level learner.view_medical permission. Deliberately includes principal (duty-of-care exception) despite the narrower default used elsewhere — see architecture doc §4. Keep in sync manually.';

-- Mirrors the app-level learner.manage_medical permission — school_owner
-- or medical_officer only (narrower than view — principal can see medical
-- info but not edit it), or any platform admin.
create or replace function public.can_manage_learner_medical(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'medical_officer')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_learner_medical(uuid) is
  'Mirrors the app-level learner.manage_medical permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Keep in sync manually.';

-- SECURITY DEFINER for the same reason current_tenant_id() is: a policy on
-- `learners` (or `learner_medical_information`) that queried
-- `learner_guardians` directly via a plain EXISTS subquery would have that
-- subquery itself evaluated under learner_guardians' own RLS — which the
-- querying guardian does not satisfy (they have no learner.view
-- permission), so the subquery would silently return no rows regardless of
-- whether the relationship exists. Verified by actually running the
-- harness: this exact bug produced false negatives on both the learners
-- and learner_medical_information guardian-access tests before this fix.
create or replace function public.is_learner_guardian(p_learner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.learner_guardians
    where learner_id = p_learner_id and guardian_profile_id = auth.uid()
  )
$$;

comment on function public.is_learner_guardian(uuid) is
  'SECURITY DEFINER to avoid recursive RLS on learner_guardians, exactly mirroring current_tenant_id()''s reason for being SECURITY DEFINER on profiles. Used by learners_select and learner_medical_information_select for guardian self-access.';

grant execute on function public.is_learner_guardian(uuid) to authenticated;
grant execute on function public.can_view_learners(uuid) to authenticated;
grant execute on function public.can_manage_learners(uuid) to authenticated;
grant execute on function public.can_view_learner_medical(uuid) to authenticated;
grant execute on function public.can_manage_learner_medical(uuid) to authenticated;

-- learners: can_view_learners covers staff directory access; profile_id =
-- auth.uid() is the learner's own self-access (if they ever have portal
-- access); is_learner_guardian() is guardian self-access to their own
-- linked learner's record. Same shape as
-- profiles_select_own_or_tenant_or_platform_admin's `id = auth.uid()`
-- clause and employees_select's `profile_id = auth.uid()` clause.
create policy learners_select on public.learners
  for select to authenticated using (
    public.can_view_learners(school_id)
    or profile_id = auth.uid()
    or public.is_learner_guardian(id)
  );
create policy learners_insert on public.learners
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy learners_update on public.learners
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

-- learner_enrollments / learner_guardians / learner_emergency_contacts /
-- learner_documents: staff-side access only (can_view_learners /
-- can_manage_learners). The locked architecture's access matrix specifies
-- guardian/self "own only" viewing explicitly for learners and for
-- learner_medical_information, but not explicitly for these four child
-- tables — extending self/guardian access to them was not specified with
-- the same rigor, so it is deliberately NOT implemented here rather than
-- invented. Flagged in the Phase 1 report as a scoping question for a
-- later phase, not decided by this migration.
create policy learner_enrollments_select on public.learner_enrollments
  for select to authenticated using (public.can_view_learners(school_id));
create policy learner_enrollments_insert on public.learner_enrollments
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy learner_enrollments_update on public.learner_enrollments
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

create policy learner_guardians_select on public.learner_guardians
  for select to authenticated using (public.can_view_learners(school_id));
create policy learner_guardians_insert on public.learner_guardians
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy learner_guardians_update on public.learner_guardians
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

create policy learner_emergency_contacts_select on public.learner_emergency_contacts
  for select to authenticated using (public.can_view_learners(school_id));
create policy learner_emergency_contacts_insert on public.learner_emergency_contacts
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy learner_emergency_contacts_update on public.learner_emergency_contacts
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

create policy learner_documents_select on public.learner_documents
  for select to authenticated using (public.can_view_learners(school_id));
create policy learner_documents_insert on public.learner_documents
  for insert to authenticated with check (public.can_manage_learners(school_id));
create policy learner_documents_update on public.learner_documents
  for update to authenticated using (public.can_manage_learners(school_id)) with check (public.can_manage_learners(school_id));

-- learner_medical_information: separately gated, per the locked
-- architecture's explicit requirement for a real (not application-layer-
-- only) protection mechanism. Self/guardian access matches the matrix's
-- explicit "own child only" / "own only" cells for this table specifically.
create policy learner_medical_information_select on public.learner_medical_information
  for select to authenticated using (
    public.can_view_learner_medical(school_id)
    or exists (
      select 1 from public.learners l
      where l.id = learner_medical_information.learner_id and l.profile_id = auth.uid()
    )
    or public.is_learner_guardian(learner_id)
  );
create policy learner_medical_information_insert on public.learner_medical_information
  for insert to authenticated with check (public.can_manage_learner_medical(school_id));
create policy learner_medical_information_update on public.learner_medical_information
  for update to authenticated using (public.can_manage_learner_medical(school_id)) with check (public.can_manage_learner_medical(school_id));

-- No DELETE policy on any of the six tables — combined with FORCE ROW
-- LEVEL SECURITY, hard delete is impossible for any authenticated caller.
-- A terminal learners.status (graduated/transferred/withdrawn) is the
-- archive condition; learner_documents.active=false is its own archive
-- flag (independent lifecycle from the learner's own status).

-- ---------------------------------------------------------------------------
-- RPCs

-- change_learner_status: convenience wrapper bundling a status change with
-- its reason atomically. Not the exclusive path to change status — the
-- transition-whitelist trigger above applies uniformly to any UPDATE,
-- RPC or direct, so no set_config-flag hard block is needed here (unlike
-- academic_years.is_active, there is no cross-row atomicity invariant a
-- direct UPDATE could violate).
create or replace function public.change_learner_status(
  p_learner_id uuid,
  p_new_status public.learner_status,
  p_reason text default null
)
returns public.learners
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_result public.learners;
begin
  select school_id into v_school_id from public.learners where id = p_learner_id;
  if not found then
    raise exception 'not_found: no learner %', p_learner_id;
  end if;

  if not public.can_manage_learners(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage learners for this school';
  end if;

  update public.learners
    set status = p_new_status, status_reason = p_reason
    where id = p_learner_id
    returning * into v_result;

  return v_result;
end;
$$;

comment on function public.change_learner_status(uuid, public.learner_status, text) is
  'Sets status and status_reason atomically. Transition validity is enforced by learners_validate_status_transition() regardless of call path.';

grant execute on function public.change_learner_status(uuid, public.learner_status, text) to authenticated;

-- promote_learner: creates the new academic-year enrollment and marks the
-- prior one 'promoted' in one transaction — mirrors set_active_academic_year's
-- atomicity reasoning (avoid a transient state a naive two-step client
-- update could leave behind).
create or replace function public.promote_learner(
  p_learner_id uuid,
  p_new_academic_year_id uuid,
  p_new_grade_id uuid,
  p_new_class_id uuid
)
returns public.learner_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school_id uuid;
  v_prior_enrollment_id uuid;
  v_result public.learner_enrollments;
begin
  select school_id into v_school_id from public.learners where id = p_learner_id;
  if not found then
    raise exception 'not_found: no learner %', p_learner_id;
  end if;

  if not public.can_manage_learners(v_school_id) then
    raise exception 'insufficient_privilege: cannot manage learners for this school';
  end if;

  select id into v_prior_enrollment_id
    from public.learner_enrollments
    where learner_id = p_learner_id and enrollment_status = 'enrolled'
    order by created_at desc
    limit 1;

  if v_prior_enrollment_id is not null then
    update public.learner_enrollments set enrollment_status = 'promoted' where id = v_prior_enrollment_id;
  end if;

  insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date)
  values (v_school_id, p_learner_id, p_new_academic_year_id, p_new_grade_id, p_new_class_id, current_date)
  returning * into v_result;

  return v_result;
end;
$$;

comment on function public.promote_learner(uuid, uuid, uuid, uuid) is
  'Atomically marks the learner''s current enrolled-status enrollment as promoted and creates the new academic-year enrollment row.';

grant execute on function public.promote_learner(uuid, uuid, uuid, uuid) to authenticated;
