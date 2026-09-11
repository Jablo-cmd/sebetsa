-- Sprint 7 — Academic Assessment & Gradebook Domain
--
-- Foundation for FUNDA360's assessment engine: assessments (a test/
-- assignment/examination/project/quiz, scoped to one class + subject +
-- term) and assessment_results (one numeric mark per learner per
-- assessment). Explicitly NOT report cards, subject averages, term
-- reports, or parent visibility — see the sprint brief's own exclusion
-- list; those are future capabilities this model is designed not to block,
-- not things this migration builds.
--
-- DECISIONS RECORDED HERE (repository is the source of truth; no existing
-- assessment/gradebook taxonomy was found anywhere in this schema before
-- this migration — confirmed by inspection, not assumed):
--
-- - Integer marks, not decimal. No existing requirement anywhere in this
--   schema calls for fractional marks (attendance is the only other scored
--   domain, and it's a 3-state enum, not numeric), and integers avoid
--   floating-point comparison/storage pitfalls entirely. max_mark is also
--   integer for the same reason and so mark <= max_mark is an exact
--   integer comparison, never a rounding question.
-- - No weighting column. Nothing elsewhere in this schema (reports,
--   grades, academic structure) implies a weighted-average requirement;
--   adding one now would be inventing scope the brief explicitly warns
--   against. Easy to add later without breaking this model — assessments
--   would gain a nullable weighting column, existing rows unaffected.
-- - No comment/remark column on results. Not shown in any of the sprint
--   brief's own worked UI examples; no existing evidence calls for it.
-- - assessment_type is a small closed enum (test/assignment/examination/
--   project/quiz), not free text — exactly the sprint brief's own
--   suggested set, used because no existing taxonomy exists to defer to
--   and an uncontrolled string column is worse than a small closed set for
--   a value every report/filter will eventually group by.
-- - assessment_results has NO row for an unmarked learner — mirrors
--   attendance_records' own shape exactly: the roster (who *should* have a
--   mark) comes from learner_enrollments, same as attendance's roster
--   does; a result row existing at all means "this learner has been
--   marked". This is deliberately NOT a nullable `mark` column meaning
--   "blank" — row absence carries that meaning instead, so `mark` can stay
--   `not null` and callers never have to distinguish "explicitly recorded
--   as blank" from "never recorded", which is exactly the "blank must
--   never silently become zero" requirement the brief calls out.
-- - Archive-not-delete for assessments (`active`, no DELETE policy) —
--   matches every other entity table in this schema. No equivalent
--   archive concept for assessment_results — a result isn't an entity
--   with its own lifecycle the way an assessment/employee/learner is;
--   corrections are UPDATEs, and (matching the same "no DELETE merely
--   because it's convenient" instruction, and identical to
--   attendance_records) there is still no DELETE policy on either table.
--
-- SECURITY DEFINER — applied precisely, not reflexively (Sprint 6's own
-- verification pass found and fixed a real production-breaking bug from
-- copying this without tracing the actual query path first; the fix here
-- is to actually trace it):
--   - assessments_validate_tenant() reads academic_years/terms/classes/
--     subjects — every one of those four is gated by can_view_academic(),
--     which every role that can ever reach this trigger (teacher-variants,
--     school_owner, principal) already holds. Plain SECURITY INVOKER is
--     correct and sufficient here; no privilege escalation needed.
--   - assessment_results_validate_tenant() reads `learners` and
--     `learner_enrollments` in addition to `assessments` — those two are
--     gated by can_view_learners(), which teacher-variant roles do NOT
--     hold (exactly the gap Sprint 6 found and fixed for attendance). This
--     one genuinely needs SECURITY DEFINER, or every teacher-submitted
--     result would fail the same way every teacher-submitted attendance
--     record silently failed before that fix.
--   - can_manage_assessment() reads class_teacher_assignments, which is
--     can_view_academic()-gated (teachers already see it) — SECURITY
--     INVOKER is correct.
--   - can_manage_assessment_result() reads only `assessments`
--     (can_view_academic()-gated) — SECURITY INVOKER is correct.

create type public.assessment_type as enum ('test', 'assignment', 'examination', 'project', 'quiz');

create table public.assessments (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  term_id           uuid not null references public.terms (id),
  class_id          uuid not null references public.classes (id),
  subject_id        uuid not null references public.subjects (id),
  title             text not null,
  assessment_type   public.assessment_type not null,
  assessment_date   date not null,
  max_mark          integer not null,
  active            boolean not null default true,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint assessments_max_mark_positive check (max_mark > 0)
);

comment on table public.assessments is 'A single gradable event (test/assignment/examination/project/quiz) for one class + subject + term. Never hard-deleted — active=false is the archive state, same pattern as every other entity table in this schema.';

-- Only among active rows, so an archived duplicate never blocks a new
-- assessment reusing the same title — same reasoning as
-- class_teacher_assignments_unique_active_idx. Same title recurring across
-- different classes/subjects/terms/years is expected, not a duplicate
-- ("Mathematics Test 1" every term, every class) — only an *exact* repeat
-- within the same class+subject+term is treated as accidental.
create unique index assessments_unique_active_idx
  on public.assessments (class_id, subject_id, term_id, title)
  where active;

create index assessments_school_id_idx on public.assessments (school_id);
create index assessments_academic_year_id_idx on public.assessments (academic_year_id);
create index assessments_term_id_idx on public.assessments (term_id);
create index assessments_class_id_idx on public.assessments (class_id);
create index assessments_subject_id_idx on public.assessments (subject_id);

create trigger assessments_set_updated_at
  before update on public.assessments
  for each row
  execute function public.set_updated_at();

create trigger assessments_set_created_updated_by
  before insert or update on public.assessments
  for each row
  execute function public.set_created_updated_by();

create or replace function public.assessments_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_year_school_id uuid;
  v_term_school_id uuid;
  v_term_academic_year_id uuid;
  v_class_school_id uuid;
  v_subject_school_id uuid;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id, academic_year_id into v_term_school_id, v_term_academic_year_id
    from public.terms where id = new.term_id;
  if v_term_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: term_id must belong to the same school';
  end if;
  if v_term_academic_year_id is distinct from new.academic_year_id then
    raise exception 'insufficient_privilege: term_id must belong to the same academic year';
  end if;

  select school_id into v_class_school_id from public.classes where id = new.class_id;
  if v_class_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: class_id must belong to the same school';
  end if;

  select school_id into v_subject_school_id from public.subjects where id = new.subject_id;
  if v_subject_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: subject_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger assessments_validate_tenant_trigger
  before insert or update on public.assessments
  for each row
  execute function public.assessments_validate_tenant();

create table public.assessment_results (
  id             uuid primary key default gen_random_uuid(),
  school_id      uuid not null references public.schools (id) on delete cascade,
  assessment_id  uuid not null references public.assessments (id) on delete cascade,
  learner_id     uuid not null references public.learners (id) on delete cascade,
  mark           integer not null,
  created_by     uuid references public.profiles (id) on delete set null,
  updated_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint assessment_results_mark_non_negative check (mark >= 0)
);

comment on table public.assessment_results is 'One row per (assessment, learner) that has actually been marked — row absence means "not yet entered", never a nullable mark meaning blank. mark <= assessments.max_mark is enforced by assessment_results_validate_tenant() (a trigger, not a CHECK, since Postgres CHECK constraints cannot reference another table). No DELETE policy — a mismarked entry is corrected via UPDATE, same as every other table in this schema.';

create unique index assessment_results_unique_idx on public.assessment_results (assessment_id, learner_id);
create index assessment_results_school_id_idx on public.assessment_results (school_id);
create index assessment_results_assessment_id_idx on public.assessment_results (assessment_id);
create index assessment_results_learner_id_idx on public.assessment_results (learner_id);

create trigger assessment_results_set_updated_at
  before update on public.assessment_results
  for each row
  execute function public.set_updated_at();

create trigger assessment_results_set_created_updated_by
  before insert or update on public.assessment_results
  for each row
  execute function public.set_created_updated_by();

-- SECURITY DEFINER — reads learners/learner_enrollments, both gated by
-- can_view_learners(), which teacher-variant roles do not hold. See the
-- migration header for why this one specifically needs it and the other
-- three new functions in this migration do not.
create or replace function public.assessment_results_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assessment record;
  v_learner_school_id uuid;
  v_enrolled boolean;
begin
  select school_id, class_id, academic_year_id, max_mark
    into v_assessment
    from public.assessments
    where id = new.assessment_id;

  if v_assessment.school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: assessment_id must belong to the same school';
  end if;

  if new.mark > v_assessment.max_mark then
    raise exception 'insufficient_privilege: mark cannot exceed the assessment''s maximum mark';
  end if;

  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select exists (
    select 1 from public.learner_enrollments
    where learner_id = new.learner_id
      and class_id = v_assessment.class_id
      and academic_year_id = v_assessment.academic_year_id
      and enrollment_status = 'enrolled'
  ) into v_enrolled;
  if not v_enrolled then
    raise exception 'insufficient_privilege: learner_id must be actively enrolled in the assessment''s class';
  end if;

  return new;
end;
$$;

create trigger assessment_results_validate_tenant_trigger
  before insert or update on public.assessment_results
  for each row
  execute function public.assessment_results_validate_tenant();

-- Mirrors the app-level assessment.manage permission, scoped per class:
-- broad for school_owner/principal (can_manage_academic), narrow — their
-- own assigned classes only — for teacher-variant roles. Same shape as
-- Attendance's can_record_attendance(), deliberately NOT reused directly
-- across domains (a function named for one domain being called from
-- another's RLS reads as confusing coupling, and Sprint 6 hardening
-- explicitly should not be touched to accommodate this sprint) —
-- duplicated logic, not duplicated risk.
create or replace function public.can_manage_assessment(target_school_id uuid, target_class_id uuid)
returns boolean
language sql
stable
as $$
  select
    public.can_manage_academic(target_school_id)
    or exists (
      select 1 from public.class_teacher_assignments cta
      where cta.class_id = target_class_id
        and cta.teacher_profile_id = auth.uid()
        and cta.active
    )
$$;

comment on function public.can_manage_assessment(uuid, uuid) is
  'Mirrors the app-level assessment.manage permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts), scoped per class via class_teacher_assignments for teacher-variant roles. Keep in sync manually.';

-- Resolves an assessment_id to its class_id and delegates to
-- can_manage_assessment() — used by assessment_results' own INSERT/UPDATE
-- policies, which only carry assessment_id, not class_id, directly.
create or replace function public.can_manage_assessment_result(target_school_id uuid, target_assessment_id uuid)
returns boolean
language sql
stable
as $$
  select public.can_manage_assessment(target_school_id, class_id)
  from public.assessments
  where id = target_assessment_id
$$;

comment on function public.can_manage_assessment_result(uuid, uuid) is
  'Resolves target_assessment_id to its class_id and delegates to can_manage_assessment(). Mirrors the app-level assessment.manage permission for the results table.';

grant execute on function public.can_manage_assessment(uuid, uuid) to authenticated;
grant execute on function public.can_manage_assessment_result(uuid, uuid) to authenticated;

alter table public.assessments enable row level security;
alter table public.assessments force row level security;

create policy assessments_select on public.assessments
  for select to authenticated using (public.can_view_academic(school_id));
create policy assessments_insert on public.assessments
  for insert to authenticated with check (public.can_manage_assessment(school_id, class_id));
create policy assessments_update on public.assessments
  for update to authenticated using (public.can_manage_assessment(school_id, class_id)) with check (public.can_manage_assessment(school_id, class_id));

alter table public.assessment_results enable row level security;
alter table public.assessment_results force row level security;

create policy assessment_results_select on public.assessment_results
  for select to authenticated using (public.can_view_academic(school_id));
create policy assessment_results_insert on public.assessment_results
  for insert to authenticated with check (public.can_manage_assessment_result(school_id, assessment_id));
create policy assessment_results_update on public.assessment_results
  for update to authenticated using (public.can_manage_assessment_result(school_id, assessment_id)) with check (public.can_manage_assessment_result(school_id, assessment_id));
