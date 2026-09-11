-- Sprint 4 — Teaching Assignment Domain
--
-- Resolves the gap recorded in ADR-0001-teaching-assignment-domain.md: the
-- `teacher`/`class_teacher`/`subject_teacher` roles have existed since
-- Milestone 5 with identical permissions and no data relationship backing
-- the distinction their names imply. This migration adds that relationship,
-- built as a real capability (school administration needs to know who
-- teaches what) rather than speculatively, per the ADR's own conclusion
-- ("should be designed once a real capability's actual needs are known").
--
-- Design decisions, each resolving one of the ADR's explicitly deferred
-- questions:
--   - Employee vs profile: assignments reference profiles directly (not
--     employees), matching learner_guardians.guardian_profile_id and
--     is_learner_guardian() — the person doing the teaching is identified
--     by their login/role, not their (optional) HR employee record.
--   - Class assignment shape: one table models both "class teacher" (the
--     person generally responsible for a class — subject_id null) and
--     "subject teacher" (responsible for one subject within a class —
--     subject_id set), rather than two separate tables. This mirrors how
--     the role catalogue itself treats the two as variants of one concept.
--   - Multiplicity: unconstrained — a class may have several subject
--     teachers and, in principle, co-assigned class teachers; nothing here
--     invents a "one primary" rule the brief never specified.
--   - Temporal validity: assignments are scoped to academic_year_id,
--     reusing the existing academic-year time-boundary concept rather than
--     inventing a new one.
--   - Historical assignments: never hard-deleted (active=false is the
--     archive state, the same pattern as every other module) — a new
--     academic year's assignments are new rows, so last year's remain
--     queryable.
--
-- Reuses academic.view/academic.manage wholesale rather than inventing new
-- permissions: can_view_academic() already includes exactly
-- school_owner/principal/teacher/class_teacher/subject_teacher (the same
-- set that would ever plausibly need to see teaching assignments), and
-- can_manage_academic() already includes exactly school_owner/principal.
-- A teacher already sees the whole academic structure under this
-- permission (classes/grades/subjects/terms) — seeing the assignment
-- roster is not more sensitive than that, so no narrower self-only RLS
-- clause is needed either; "my classes" is a client-side filter over the
-- same permitted rows, the same shape as other self-service views.

create table public.class_teacher_assignments (
  id                  uuid primary key default gen_random_uuid(),
  school_id           uuid not null references public.schools (id) on delete cascade,
  academic_year_id    uuid not null references public.academic_years (id),
  class_id            uuid not null references public.classes (id),
  subject_id          uuid references public.subjects (id),
  teacher_profile_id  uuid not null references public.profiles (id) on delete cascade,
  active              boolean not null default true,
  created_by          uuid references public.profiles (id) on delete set null,
  updated_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.class_teacher_assignments is 'Which teacher (profile) is responsible for a class overall (subject_id null) or for one subject within a class (subject_id set), for a given academic year. Never hard-deleted — active=false is the archive state.';
comment on column public.class_teacher_assignments.subject_id is 'NULL = a "class teacher" assignment (whole class); set = a "subject teacher" assignment (one subject within the class).';

-- Only among active rows, so an archived duplicate never blocks a new
-- assignment — same reasoning as learner_guardians_one_primary_per_learner
-- being a partial index. coalesce() handles subject_id being NULL, since a
-- plain unique constraint would never treat two NULLs as equal.
create unique index class_teacher_assignments_unique_active_idx
  on public.class_teacher_assignments (
    academic_year_id, class_id, coalesce(subject_id, '00000000-0000-0000-0000-000000000000'::uuid), teacher_profile_id
  )
  where active;

create index class_teacher_assignments_school_id_idx on public.class_teacher_assignments (school_id);
create index class_teacher_assignments_class_id_idx on public.class_teacher_assignments (class_id);
create index class_teacher_assignments_teacher_profile_id_idx on public.class_teacher_assignments (teacher_profile_id);
create index class_teacher_assignments_academic_year_id_idx on public.class_teacher_assignments (academic_year_id);

create trigger class_teacher_assignments_set_updated_at
  before update on public.class_teacher_assignments
  for each row
  execute function public.set_updated_at();

create trigger class_teacher_assignments_set_created_updated_by
  before insert or update on public.class_teacher_assignments
  for each row
  execute function public.set_created_updated_by();

-- Closes the FK-doesn't-respect-RLS gap for every reference this row
-- makes, same pattern as learner_enrollments_validate_tenant_and_grade().
create or replace function public.class_teacher_assignments_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_year_school_id uuid;
  v_class_school_id uuid;
  v_subject_school_id uuid;
  v_teacher_tenant_id uuid;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id into v_class_school_id from public.classes where id = new.class_id;
  if v_class_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: class_id must belong to the same school';
  end if;

  if new.subject_id is not null then
    select school_id into v_subject_school_id from public.subjects where id = new.subject_id;
    if v_subject_school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: subject_id must belong to the same school';
    end if;
  end if;

  select tenant_id into v_teacher_tenant_id from public.profiles where id = new.teacher_profile_id;
  if v_teacher_tenant_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: teacher_profile_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger class_teacher_assignments_validate_tenant_trigger
  before insert or update on public.class_teacher_assignments
  for each row
  execute function public.class_teacher_assignments_validate_tenant();

alter table public.class_teacher_assignments enable row level security;
alter table public.class_teacher_assignments force row level security;

create policy class_teacher_assignments_select on public.class_teacher_assignments
  for select to authenticated using (public.can_view_academic(school_id));
create policy class_teacher_assignments_insert on public.class_teacher_assignments
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy class_teacher_assignments_update on public.class_teacher_assignments
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete is
-- impossible for any authenticated caller, same as every other archive-only
-- table in this schema.
