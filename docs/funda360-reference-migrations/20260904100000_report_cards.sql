-- Report Cards domain (2/2) — templates, the report_card entity, the
-- Draft -> Teacher Review -> HOD Review -> Approved -> Published ->
-- Archived workflow, versioning/reissue, and mark/attendance/conduct
-- aggregation.
--
-- REUSE, NOT DUPLICATION:
--   marks       -> assessments + assessment_results (unchanged; this
--                  migration only adds the `weight` column the assessments
--                  migration itself named as the extension path for
--                  weighting: "assessments would gain a nullable weighting
--                  column, existing rows unaffected")
--   scale       -> grading_scales / resolve_achievement() (20260904090000)
--   enrolment   -> learner_enrollments (grade_id/class_id for the term)
--   teachers    -> class_teacher_assignments (subject teacher = whose
--                  comment; class teacher = whose class-teacher comment)
--   attendance  -> attendance_records (term-date-range tally)
--   conduct     -> behaviour_incidents (term-date-range tally)
--   audit       -> write_audit_log()
--   notify      -> create_notification()
--
-- NO CLIENT-TRUSTED WORKFLOW STATE: report_cards / report_card_subjects
-- have NO INSERT/UPDATE/DELETE policy for `authenticated`. Every field is
-- written only by the SECURITY DEFINER RPCs below, each of which
-- re-derives the caller's authority from the database (role + class-
-- teacher assignment), never from anything the client sends. A trigger
-- blocks any direct write that isn't inside one of those RPCs (the
-- app.allow_report_card_write guard, same pattern as invoices /
-- bank reconciliation).
--
-- LOCKING: once status reaches approved/published/archived the card and
-- its subject rows are immutable — recalculation, comment edits and
-- promotion changes all reject. The only way to change a published card is
-- reissue_report_card(), which creates a new version in draft and archives
-- the old one (never edits it in place).
--
-- VISIBILITY: staff with academic.view see every status (needed for the
-- workflow UI and staff preview). A guardian sees ONLY status='published'
-- for their own linked child; a learner sees ONLY status='published' for
-- their own record (learners.profile_id = auth.uid()). Nothing else.

-- ---------------------------------------------------------------------------
-- 0. Per-assessment weighting — the documented assessments extension.

alter table public.assessments
  add column if not exists weight numeric(5, 2) not null default 1 check (weight > 0);

comment on column public.assessments.weight is 'Relative weight of this assessment when a report card aggregates a subject mark (e.g. an exam weighted 3, a class test weighted 1). Default 1 = the prior unweighted mean-of-percentages behaviour, so existing rows and the ad-hoc transcript PDF are unaffected.';

-- ---------------------------------------------------------------------------
-- 1. Enums.

create type public.report_card_status as enum
  ('draft', 'teacher_review', 'hod_review', 'approved', 'published', 'archived');

create type public.report_card_promotion as enum
  ('promoted', 'promoted_conditionally', 'retained', 'not_applicable');

-- ---------------------------------------------------------------------------
-- 2. report_card_templates — the school's configurable layouts.

create table public.report_card_templates (
  id                          uuid primary key default gen_random_uuid(),
  school_id                   uuid not null references public.schools (id) on delete cascade,
  name                        text not null check (char_length(name) > 0),
  grading_scale_id            uuid not null references public.grading_scales (id),
  is_default                  boolean not null default false,
  active                      boolean not null default true,
  show_attendance             boolean not null default true,
  show_conduct                boolean not null default true,
  show_class_teacher_comment  boolean not null default true,
  show_principal_comment      boolean not null default true,
  show_subject_comments       boolean not null default true,
  show_promotion              boolean not null default true,
  requires_hod_review         boolean not null default false,
  header_note                 text,
  footer_note                 text,
  created_by                  uuid references public.profiles (id) on delete set null,
  updated_by                  uuid references public.profiles (id) on delete set null,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

comment on table public.report_card_templates is 'A configurable report-card layout: which sections appear, whether an HOD-review step is required, and which grading scale resolves achievement codes. Never hard-deleted — active=false is the archive state.';
comment on column public.report_card_templates.requires_hod_review is 'When true, approve_report_card() rejects unless the card has passed through hod_review. When false the HOD step is optional (a card may still be sent for HOD review, but approval does not require it).';

create index report_card_templates_school_id_idx on public.report_card_templates (school_id);
create unique index report_card_templates_school_id_name_key on public.report_card_templates (school_id, lower(name));
create unique index report_card_templates_one_default_per_school on public.report_card_templates (school_id) where is_default and active;

create trigger report_card_templates_set_updated_at
  before update on public.report_card_templates
  for each row execute function public.set_updated_at();

create trigger report_card_templates_set_created_updated_by
  before insert or update on public.report_card_templates
  for each row execute function public.set_created_updated_by();

create or replace function public.report_card_templates_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scale_school_id uuid;
begin
  select school_id into v_scale_school_id from public.grading_scales where id = new.grading_scale_id;
  if v_scale_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: grading_scale_id must belong to the same school';
  end if;
  return new;
end;
$$;

create trigger report_card_templates_validate_trigger
  before insert or update on public.report_card_templates
  for each row execute function public.report_card_templates_validate();

-- ---------------------------------------------------------------------------
-- 3. report_card_batches — a bulk-generation event record (create-only,
-- like bank_reconciliation_imports).

create table public.report_card_batches (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  term_id           uuid not null references public.terms (id),
  class_id          uuid not null references public.classes (id),
  template_id       uuid not null references public.report_card_templates (id),
  generated_count   integer not null default 0,
  skipped_count     integer not null default 0,
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now()
);

comment on table public.report_card_batches is 'One row per generate_report_cards_for_class() call — an audit record of a bulk generation. The report_cards it produced link back via batch_id.';

create index report_card_batches_school_id_idx on public.report_card_batches (school_id);
create index report_card_batches_class_term_idx on public.report_card_batches (class_id, term_id);

-- ---------------------------------------------------------------------------
-- 4. report_cards.

create table public.report_cards (
  id                           uuid primary key default gen_random_uuid(),
  school_id                    uuid not null references public.schools (id) on delete cascade,
  learner_id                   uuid not null references public.learners (id) on delete cascade,
  academic_year_id             uuid not null references public.academic_years (id),
  term_id                      uuid not null references public.terms (id),
  grade_id                     uuid not null references public.grades (id),
  class_id                     uuid not null references public.classes (id),
  template_id                  uuid not null references public.report_card_templates (id),
  batch_id                     uuid references public.report_card_batches (id) on delete set null,
  version                      integer not null default 1 check (version >= 1),
  status                       public.report_card_status not null default 'draft',
  superseded_by                uuid references public.report_cards (id) on delete set null,
  learner_name                 text not null,
  learner_number               text not null,
  class_teacher_comment        text,
  principal_comment            text,
  conduct_summary              text,
  promotion_status             public.report_card_promotion not null default 'not_applicable',
  overall_average_percentage   numeric(5, 2),
  overall_achievement_code     text,
  overall_achievement_label    text,
  attendance_present           integer not null default 0,
  attendance_absent            integer not null default 0,
  attendance_late              integer not null default 0,
  attendance_excused           integer not null default 0,
  attendance_total_days        integer not null default 0,
  conduct_positive_count       integer not null default 0,
  conduct_negative_count       integer not null default 0,
  generated_at                 timestamptz not null default now(),
  submitted_at                 timestamptz,
  submitted_by                 uuid references public.profiles (id) on delete set null,
  reviewed_at                  timestamptz,
  reviewed_by                  uuid references public.profiles (id) on delete set null,
  approved_at                  timestamptz,
  approved_by                  uuid references public.profiles (id) on delete set null,
  published_at                 timestamptz,
  published_by                 uuid references public.profiles (id) on delete set null,
  archived_at                  timestamptz,
  locked_at                    timestamptz,
  created_by                   uuid references public.profiles (id) on delete set null,
  updated_by                   uuid references public.profiles (id) on delete set null,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),
  unique (learner_id, term_id, template_id, version)
);

comment on table public.report_cards is 'One learner''s report card for one term against one template, at one version. All fields are RPC-written only (no client write policy + report_cards_protect trigger). Aggregate columns (overall_*, attendance_*, conduct_*) are a snapshot recomputed by recalculate_report_card() while the card is still editable, then frozen at approval.';
comment on column public.report_cards.status is 'draft -> teacher_review -> (hod_review) -> approved -> published -> archived. Transitions only via the workflow RPCs; approved/published/archived are locked (immutable).';
comment on column public.report_cards.superseded_by is 'Set by reissue_report_card() on the OLD card, pointing at the new-version card that replaces it. The old card is also moved to status=archived in the same call.';

create unique index report_cards_one_live_per_learner_term_template
  on public.report_cards (learner_id, term_id, template_id)
  where status <> 'archived';

create index report_cards_school_id_idx on public.report_cards (school_id);
create index report_cards_learner_id_idx on public.report_cards (learner_id);
create index report_cards_term_id_idx on public.report_cards (term_id);
create index report_cards_class_term_status_idx on public.report_cards (class_id, term_id, status);
create index report_cards_batch_id_idx on public.report_cards (batch_id);

create trigger report_cards_set_updated_at
  before update on public.report_cards
  for each row execute function public.set_updated_at();

create trigger report_cards_set_created_updated_by
  before insert or update on public.report_cards
  for each row execute function public.set_created_updated_by();

-- ---------------------------------------------------------------------------
-- 5. report_card_subjects.

create table public.report_card_subjects (
  id                   uuid primary key default gen_random_uuid(),
  report_card_id       uuid not null references public.report_cards (id) on delete cascade,
  school_id            uuid not null references public.schools (id) on delete cascade,
  subject_id           uuid not null references public.subjects (id),
  subject_name         text not null,
  teacher_profile_id   uuid references public.profiles (id) on delete set null,
  teacher_name         text,
  weight               numeric(5, 2) not null default 1 check (weight > 0),
  average_percentage   numeric(5, 2),
  achievement_code     text,
  achievement_label    text,
  teacher_comment      text,
  assessment_count     integer not null default 0,
  sort_order           integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (report_card_id, subject_id)
);

comment on table public.report_card_subjects is 'One subject line on a report card. average_percentage is the assessment.weight-weighted mean of (mark/max_mark) across the learner''s active assessment_results for this subject+term+class; NULL means no marks were recorded. weight is this subject''s contribution to the card''s overall average.';

create index report_card_subjects_report_card_id_idx on public.report_card_subjects (report_card_id);
create index report_card_subjects_school_id_idx on public.report_card_subjects (school_id);

create trigger report_card_subjects_set_updated_at
  before update on public.report_card_subjects
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Tenant-validation + lifecycle-protection triggers.

create or replace function public.report_cards_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_learner_school uuid;
  v_year_school uuid;
  v_term record;
  v_grade_school uuid;
  v_class record;
  v_template_school uuid;
begin
  select school_id into v_learner_school from public.learners where id = new.learner_id;
  if v_learner_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  select school_id into v_year_school from public.academic_years where id = new.academic_year_id;
  if v_year_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id, academic_year_id into v_term from public.terms where id = new.term_id;
  if v_term.school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: term_id must belong to the same school';
  end if;
  if v_term.academic_year_id is distinct from new.academic_year_id then
    raise exception 'insufficient_privilege: term_id must belong to the same academic year';
  end if;

  select school_id into v_grade_school from public.grades where id = new.grade_id;
  if v_grade_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: grade_id must belong to the same school';
  end if;

  select school_id, grade_id into v_class from public.classes where id = new.class_id;
  if v_class.school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: class_id must belong to the same school';
  end if;

  select school_id into v_template_school from public.report_card_templates where id = new.template_id;
  if v_template_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: template_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger report_cards_validate_tenant_trigger
  before insert or update on public.report_cards
  for each row execute function public.report_cards_validate_tenant();

create or replace function public.report_card_subjects_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc_school uuid;
  v_subject_school uuid;
begin
  select school_id into v_rc_school from public.report_cards where id = new.report_card_id;
  if v_rc_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: report_card_id must belong to the same school';
  end if;
  select school_id into v_subject_school from public.subjects where id = new.subject_id;
  if v_subject_school is distinct from new.school_id then
    raise exception 'insufficient_privilege: subject_id must belong to the same school';
  end if;
  return new;
end;
$$;

create trigger report_card_subjects_validate_tenant_trigger
  before insert or update on public.report_card_subjects
  for each row execute function public.report_card_subjects_validate_tenant();

-- Every mutation of a report card / its subjects must go through a
-- workflow RPC (which sets app.allow_report_card_write). A direct client
-- UPDATE (there is no policy for one, but defence in depth) is rejected.
create or replace function public.report_cards_protect()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('app.allow_report_card_write', true), '') <> 'true' then
    raise exception 'insufficient_privilege: report cards are managed only through the report-card workflow functions';
  end if;
  return new;
end;
$$;

create trigger report_cards_protect_trigger
  before update on public.report_cards
  for each row execute function public.report_cards_protect();

create trigger report_card_subjects_protect_trigger
  before insert or update on public.report_card_subjects
  for each row execute function public.report_cards_protect();

-- ---------------------------------------------------------------------------
-- 7. Authorization helpers.

-- Mirrors "who may build/edit a report card": academic managers school-
-- wide, or a teacher assigned to that specific class (class teacher or any
-- subject teacher). Same shape as can_manage_assessment().
create or replace function public.can_manage_report_card(target_school_id uuid, target_class_id uuid)
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

comment on function public.can_manage_report_card(uuid, uuid) is
  'Mirrors "may generate/recalculate/submit a report card / edit a subject comment": can_manage_academic() school-wide, or an active class_teacher_assignments row for the caller on that class. Keep in sync manually with ROLE_PERMISSIONS.';

grant execute on function public.can_manage_report_card(uuid, uuid) to authenticated;

-- Is the caller the CLASS teacher (subject_id null) for this class?
create or replace function public.is_class_teacher_for(target_class_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.class_teacher_assignments cta
    where cta.class_id = target_class_id
      and cta.subject_id is null
      and cta.teacher_profile_id = auth.uid()
      and cta.active
  )
$$;

grant execute on function public.is_class_teacher_for(uuid) to authenticated;

-- Mirrors the app-level reportcard.view permission — broader than
-- can_view_academic() because an HOD (department_head) and a
-- vice_principal must be able to read report cards for the review/oversight
-- workflow without also being granted the whole academic catalogue.
create or replace function public.can_view_report_cards(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'vice_principal', 'department_head', 'teacher', 'class_teacher', 'subject_teacher')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_report_cards(uuid) is
  'Mirrors the app-level reportcard.view permission (ROLE_PERMISSIONS). A superset of can_view_academic() by department_head + vice_principal. Keep in sync manually.';

grant execute on function public.can_view_report_cards(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. RLS.

alter table public.report_card_templates enable row level security;
alter table public.report_card_templates force row level security;
alter table public.report_card_batches enable row level security;
alter table public.report_card_batches force row level security;
alter table public.report_cards enable row level security;
alter table public.report_cards force row level security;
alter table public.report_card_subjects enable row level security;
alter table public.report_card_subjects force row level security;

create policy report_card_templates_select on public.report_card_templates
  for select to authenticated using (public.can_view_report_cards(school_id));
create policy report_card_templates_insert on public.report_card_templates
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy report_card_templates_update on public.report_card_templates
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

-- batches: staff read-only; created only by the generation RPC.
create policy report_card_batches_select on public.report_card_batches
  for select to authenticated using (public.can_view_report_cards(school_id));

-- report_cards: staff see all statuses; guardian/learner see own + published only.
create policy report_cards_select_staff on public.report_cards
  for select to authenticated using (public.can_view_report_cards(school_id));
create policy report_cards_select_guardian on public.report_cards
  for select to authenticated using (status = 'published' and public.is_learner_guardian(learner_id));
create policy report_cards_select_learner on public.report_cards
  for select to authenticated using (
    status = 'published'
    and exists (select 1 from public.learners l where l.id = learner_id and l.profile_id = auth.uid())
  );
-- No INSERT/UPDATE/DELETE policy — workflow RPCs only.

create policy report_card_subjects_select_staff on public.report_card_subjects
  for select to authenticated using (public.can_view_report_cards(school_id));
create policy report_card_subjects_select_guardian on public.report_card_subjects
  for select to authenticated using (
    exists (
      select 1 from public.report_cards rc
      where rc.id = report_card_id and rc.status = 'published' and public.is_learner_guardian(rc.learner_id)
    )
  );
create policy report_card_subjects_select_learner on public.report_card_subjects
  for select to authenticated using (
    exists (
      select 1 from public.report_cards rc
      join public.learners l on l.id = rc.learner_id
      where rc.id = report_card_id and rc.status = 'published' and l.profile_id = auth.uid()
    )
  );
-- No INSERT/UPDATE/DELETE policy — workflow RPCs only.

comment on policy report_cards_select_guardian on public.report_cards is
  'A guardian sees a report card for their own linked child only once it is PUBLISHED — draft/review/approved cards are internal staff working state.';

-- ---------------------------------------------------------------------------
-- 9. Aggregation — the calculation core (also unit-tested client-side).

create or replace function public.recalc_report_card_internal(p_report_card_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_scale_id uuid;
  v_term record;
  v_subj record;
  v_avg numeric(6, 3);
  v_count integer;
  v_ach record;
  v_overall_num numeric := 0;
  v_overall_den numeric := 0;
  v_overall numeric(5, 2);
  v_present integer; v_absent integer; v_late integer; v_excused integer;
  v_pos integer; v_neg integer;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then
    raise exception 'not_found: no report card %', p_report_card_id;
  end if;

  select grading_scale_id into v_scale_id from public.report_card_templates where id = v_rc.template_id;
  select start_date, end_date into v_term from public.terms where id = v_rc.term_id;

  perform set_config('app.allow_report_card_write', 'true', true);

  for v_subj in
    select id, subject_id, weight from public.report_card_subjects where report_card_id = p_report_card_id
  loop
    -- assessment.weight-weighted mean of (mark / max_mark * 100).
    select
      sum((ar.mark::numeric / a.max_mark * 100) * a.weight) / nullif(sum(a.weight), 0),
      count(*)
      into v_avg, v_count
    from public.assessment_results ar
    join public.assessments a on a.id = ar.assessment_id
    where ar.learner_id = v_rc.learner_id
      and a.subject_id = v_subj.subject_id
      and a.class_id = v_rc.class_id
      and a.term_id = v_rc.term_id
      and a.active;

    if v_avg is not null then
      select code, label into v_ach from public.resolve_achievement(v_scale_id, v_avg);
      v_overall_num := v_overall_num + round(v_avg, 2) * v_subj.weight;
      v_overall_den := v_overall_den + v_subj.weight;
    else
      v_ach := row(null, null);
    end if;

    update public.report_card_subjects set
      average_percentage = round(v_avg, 2),
      achievement_code = v_ach.code,
      achievement_label = v_ach.label,
      assessment_count = coalesce(v_count, 0)
    where id = v_subj.id;
  end loop;

  if v_overall_den > 0 then
    v_overall := round(v_overall_num / v_overall_den, 2);
    select code, label into v_ach from public.resolve_achievement(v_scale_id, v_overall);
  else
    v_overall := null;
    v_ach := row(null, null);
  end if;

  select
    count(*) filter (where status = 'present'),
    count(*) filter (where status = 'absent'),
    count(*) filter (where status = 'late'),
    count(*) filter (where status = 'excused')
    into v_present, v_absent, v_late, v_excused
  from public.attendance_records
  where learner_id = v_rc.learner_id
    and attendance_date between v_term.start_date and v_term.end_date;

  select
    count(*) filter (where incident_type = 'positive'),
    count(*) filter (where incident_type = 'negative')
    into v_pos, v_neg
  from public.behaviour_incidents
  where learner_id = v_rc.learner_id
    and active
    and (occurred_at at time zone 'Africa/Johannesburg')::date between v_term.start_date and v_term.end_date;

  update public.report_cards set
    overall_average_percentage = v_overall,
    overall_achievement_code = v_ach.code,
    overall_achievement_label = v_ach.label,
    attendance_present = coalesce(v_present, 0),
    attendance_absent = coalesce(v_absent, 0),
    attendance_late = coalesce(v_late, 0),
    attendance_excused = coalesce(v_excused, 0),
    attendance_total_days = coalesce(v_present, 0) + coalesce(v_absent, 0) + coalesce(v_late, 0) + coalesce(v_excused, 0),
    conduct_positive_count = coalesce(v_pos, 0),
    conduct_negative_count = coalesce(v_neg, 0)
  where id = p_report_card_id;

  perform set_config('app.allow_report_card_write', 'false', true);
end;
$$;

comment on function public.recalc_report_card_internal(uuid) is
  'Recomputes a report card''s subject averages/achievements, overall average, and attendance + conduct tallies from live assessment_results / attendance_records / behaviour_incidents. Internal — callers must have already authorised and confirmed the card is still editable.';

revoke execute on function public.recalc_report_card_internal(uuid) from public;

-- Builds the subject rows for a freshly-created report card: every subject
-- taught to the class this year (class_teacher_assignments), plus any
-- subject that has an assessment for the class this term even without a
-- teaching assignment.
create or replace function public.build_report_card_subjects_internal(p_report_card_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_subj record;
  v_teacher record;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  perform set_config('app.allow_report_card_write', 'true', true);

  for v_subj in
    select s.id as subject_id, s.name as subject_name
    from public.subjects s
    where s.school_id = v_rc.school_id
      and s.active
      and (
        exists (
          select 1 from public.class_teacher_assignments cta
          where cta.class_id = v_rc.class_id and cta.academic_year_id = v_rc.academic_year_id
            and cta.subject_id = s.id and cta.active
        )
        or exists (
          select 1 from public.assessments a
          where a.class_id = v_rc.class_id and a.term_id = v_rc.term_id and a.subject_id = s.id and a.active
        )
      )
    order by s.name
  loop
    select p.id as pid, (p.first_name || ' ' || p.last_name) as pname
      into v_teacher
    from public.class_teacher_assignments cta
    join public.profiles p on p.id = cta.teacher_profile_id
    where cta.class_id = v_rc.class_id and cta.academic_year_id = v_rc.academic_year_id
      and cta.subject_id = v_subj.subject_id and cta.active
    order by cta.created_at
    limit 1;

    insert into public.report_card_subjects (report_card_id, school_id, subject_id, subject_name, teacher_profile_id, teacher_name)
    values (p_report_card_id, v_rc.school_id, v_subj.subject_id, v_subj.subject_name, v_teacher.pid, v_teacher.pname)
    on conflict (report_card_id, subject_id) do nothing;
  end loop;

  perform set_config('app.allow_report_card_write', 'false', true);
end;
$$;

revoke execute on function public.build_report_card_subjects_internal(uuid) from public;

-- Creates one draft report card (+ its subject rows, aggregated). No
-- authorization here — every caller below has already checked.
create or replace function public.create_report_card_internal(
  p_learner_id uuid, p_term_id uuid, p_template_id uuid, p_batch_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
  v_year uuid;
  v_learner record;
  v_enrol record;
  v_rc_id uuid;
begin
  select school_id, academic_year_id into v_school, v_year from public.terms where id = p_term_id;
  if v_school is null then
    raise exception 'not_found: no term %', p_term_id;
  end if;

  select school_id, first_name, last_name, learner_number into v_learner from public.learners where id = p_learner_id;
  if v_learner.school_id is distinct from v_school then
    raise exception 'insufficient_privilege: learner and term belong to different schools';
  end if;

  select grade_id, class_id into v_enrol
  from public.learner_enrollments
  where learner_id = p_learner_id and academic_year_id = v_year and enrollment_status = 'enrolled'
  order by created_at desc
  limit 1;
  if v_enrol.class_id is null then
    raise exception 'invalid_state: learner % is not enrolled in a class for this term''s academic year', p_learner_id;
  end if;

  if exists (
    select 1 from public.report_cards
    where learner_id = p_learner_id and term_id = p_term_id and template_id = p_template_id and status <> 'archived'
  ) then
    raise exception 'already_exists: a live report card already exists for this learner, term and template (recalculate or reissue it)';
  end if;

  perform set_config('app.allow_report_card_write', 'true', true);
  insert into public.report_cards (
    school_id, learner_id, academic_year_id, term_id, grade_id, class_id, template_id, batch_id,
    learner_name, learner_number
  ) values (
    v_school, p_learner_id, v_year, p_term_id, v_enrol.grade_id, v_enrol.class_id, p_template_id, p_batch_id,
    v_learner.first_name || ' ' || v_learner.last_name, v_learner.learner_number
  )
  returning id into v_rc_id;
  perform set_config('app.allow_report_card_write', 'false', true);

  perform public.build_report_card_subjects_internal(v_rc_id);
  perform public.recalc_report_card_internal(v_rc_id);

  return v_rc_id;
end;
$$;

revoke execute on function public.create_report_card_internal(uuid, uuid, uuid, uuid) from public;

-- ---------------------------------------------------------------------------
-- 10. Public workflow RPCs.

create or replace function public.generate_report_card(p_learner_id uuid, p_term_id uuid, p_template_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
  v_year uuid;
  v_class_id uuid;
  v_rc_id uuid;
  v_result public.report_cards;
begin
  select school_id, academic_year_id into v_school, v_year from public.terms where id = p_term_id;
  if v_school is null then
    raise exception 'not_found: no term %', p_term_id;
  end if;

  select class_id into v_class_id
  from public.learner_enrollments
  where learner_id = p_learner_id and academic_year_id = v_year and enrollment_status = 'enrolled'
  order by created_at desc limit 1;
  if v_class_id is null then
    raise exception 'invalid_state: learner is not enrolled in a class for this term''s academic year';
  end if;

  if not public.can_manage_report_card(v_school, v_class_id) then
    raise exception 'insufficient_privilege: not permitted to generate report cards for this class';
  end if;

  v_rc_id := public.create_report_card_internal(p_learner_id, p_term_id, p_template_id, null);
  perform public.write_audit_log(v_school, auth.uid(), 'report_card_generated', 'report_cards', v_rc_id,
    null, jsonb_build_object('learner_id', p_learner_id, 'term_id', p_term_id, 'template_id', p_template_id));

  select * into v_result from public.report_cards where id = v_rc_id;
  return v_result;
end;
$$;

revoke execute on function public.generate_report_card(uuid, uuid, uuid) from public;
grant execute on function public.generate_report_card(uuid, uuid, uuid) to authenticated;

create or replace function public.generate_report_cards_for_class(p_class_id uuid, p_term_id uuid, p_template_id uuid)
returns public.report_card_batches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
  v_year uuid;
  v_class_school uuid;
  v_batch_id uuid;
  v_learner uuid;
  v_generated integer := 0;
  v_skipped integer := 0;
  v_result public.report_card_batches;
begin
  select school_id, academic_year_id into v_school, v_year from public.terms where id = p_term_id;
  if v_school is null then
    raise exception 'not_found: no term %', p_term_id;
  end if;
  select school_id into v_class_school from public.classes where id = p_class_id;
  if v_class_school is distinct from v_school then
    raise exception 'insufficient_privilege: class and term belong to different schools';
  end if;
  if not public.can_manage_report_card(v_school, p_class_id) then
    raise exception 'insufficient_privilege: not permitted to generate report cards for this class';
  end if;

  insert into public.report_card_batches (school_id, academic_year_id, term_id, class_id, template_id, created_by)
  values (v_school, v_year, p_term_id, p_class_id, p_template_id, auth.uid())
  returning id into v_batch_id;

  for v_learner in
    select learner_id from public.learner_enrollments
    where class_id = p_class_id and academic_year_id = v_year and enrollment_status = 'enrolled'
  loop
    if exists (
      select 1 from public.report_cards
      where learner_id = v_learner and term_id = p_term_id and template_id = p_template_id and status <> 'archived'
    ) then
      v_skipped := v_skipped + 1;
    else
      perform public.create_report_card_internal(v_learner, p_term_id, p_template_id, v_batch_id);
      v_generated := v_generated + 1;
    end if;
  end loop;

  update public.report_card_batches set generated_count = v_generated, skipped_count = v_skipped where id = v_batch_id;

  perform public.write_audit_log(v_school, auth.uid(), 'report_card_batch_generated', 'report_card_batches', v_batch_id,
    null, jsonb_build_object('class_id', p_class_id, 'term_id', p_term_id, 'generated', v_generated, 'skipped', v_skipped));

  select * into v_result from public.report_card_batches where id = v_batch_id;
  return v_result;
end;
$$;

revoke execute on function public.generate_report_cards_for_class(uuid, uuid, uuid) from public;
grant execute on function public.generate_report_cards_for_class(uuid, uuid, uuid) to authenticated;

-- Internal: load a card, check the caller may manage it, check it is still
-- editable. Raises otherwise. Returns the row.
create or replace function public.report_card_editable_guard(p_report_card_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then
    raise exception 'not_found: no report card %', p_report_card_id;
  end if;
  if not public.can_manage_report_card(v_rc.school_id, v_rc.class_id) then
    raise exception 'insufficient_privilege: not permitted to manage this report card';
  end if;
  if v_rc.status not in ('draft', 'teacher_review', 'hod_review') then
    raise exception 'report_card_locked: this report card is % and can no longer be edited', v_rc.status;
  end if;
  return v_rc;
end;
$$;

revoke execute on function public.report_card_editable_guard(uuid) from public;

create or replace function public.recalculate_report_card(p_report_card_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_result public.report_cards;
begin
  v_rc := public.report_card_editable_guard(p_report_card_id);
  perform public.build_report_card_subjects_internal(p_report_card_id);
  perform public.recalc_report_card_internal(p_report_card_id);
  perform public.write_audit_log(v_rc.school_id, auth.uid(), 'report_card_recalculated', 'report_cards', p_report_card_id, null, null);
  select * into v_result from public.report_cards where id = p_report_card_id;
  return v_result;
end;
$$;

revoke execute on function public.recalculate_report_card(uuid) from public;
grant execute on function public.recalculate_report_card(uuid) to authenticated;

create or replace function public.set_report_card_subject_comment(p_subject_row_id uuid, p_comment text)
returns public.report_card_subjects
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.report_card_subjects;
  v_rc public.report_cards;
  v_result public.report_card_subjects;
begin
  select * into v_row from public.report_card_subjects where id = p_subject_row_id;
  if not found then
    raise exception 'not_found: no report card subject row %', p_subject_row_id;
  end if;
  select * into v_rc from public.report_cards where id = v_row.report_card_id;
  if v_rc.status not in ('draft', 'teacher_review', 'hod_review') then
    raise exception 'report_card_locked: this report card is % and can no longer be edited', v_rc.status;
  end if;

  if not (
    public.can_manage_academic(v_rc.school_id)
    or v_row.teacher_profile_id = auth.uid()
    or exists (
      select 1 from public.class_teacher_assignments cta
      where cta.class_id = v_rc.class_id and cta.teacher_profile_id = auth.uid() and cta.active
        and (cta.subject_id = v_row.subject_id or cta.subject_id is null)
    )
  ) then
    raise exception 'insufficient_privilege: only this subject''s teacher or an academic manager may edit this comment';
  end if;

  perform set_config('app.allow_report_card_write', 'true', true);
  update public.report_card_subjects set teacher_comment = nullif(trim(p_comment), '') where id = p_subject_row_id
  returning * into v_result;
  perform set_config('app.allow_report_card_write', 'false', true);

  perform public.write_audit_log(v_rc.school_id, auth.uid(), 'report_card_subject_comment_set', 'report_card_subjects', p_subject_row_id, null,
    jsonb_build_object('subject_id', v_row.subject_id));
  return v_result;
end;
$$;

revoke execute on function public.set_report_card_subject_comment(uuid, text) from public;
grant execute on function public.set_report_card_subject_comment(uuid, text) to authenticated;

create or replace function public.set_report_card_comment(p_report_card_id uuid, p_field text, p_text text)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_result public.report_cards;
  v_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  if p_field not in ('class_teacher_comment', 'principal_comment', 'conduct_summary') then
    raise exception 'invalid_argument: field must be class_teacher_comment, principal_comment or conduct_summary';
  end if;

  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then
    raise exception 'not_found: no report card %', p_report_card_id;
  end if;
  if v_rc.status not in ('draft', 'teacher_review', 'hod_review') then
    raise exception 'report_card_locked: this report card is % and can no longer be edited', v_rc.status;
  end if;

  if p_field = 'principal_comment' then
    if not (public.can_manage_academic(v_rc.school_id)) then
      raise exception 'insufficient_privilege: only a principal or school owner may set the principal comment';
    end if;
  elsif p_field = 'class_teacher_comment' then
    if not (public.can_manage_academic(v_rc.school_id) or public.is_class_teacher_for(v_rc.class_id)) then
      raise exception 'insufficient_privilege: only the class teacher or an academic manager may set the class-teacher comment';
    end if;
  else -- conduct_summary
    if not public.can_manage_report_card(v_rc.school_id, v_rc.class_id) then
      raise exception 'insufficient_privilege: not permitted to edit this report card';
    end if;
  end if;

  perform set_config('app.allow_report_card_write', 'true', true);
  execute format('update public.report_cards set %I = $1 where id = $2', p_field)
    using nullif(trim(p_text), ''), p_report_card_id;
  perform set_config('app.allow_report_card_write', 'false', true);

  perform public.write_audit_log(v_rc.school_id, auth.uid(), 'report_card_comment_set', 'report_cards', p_report_card_id, null,
    jsonb_build_object('field', p_field));
  select * into v_result from public.report_cards where id = p_report_card_id;
  return v_result;
end;
$$;

revoke execute on function public.set_report_card_comment(uuid, text, text) from public;
grant execute on function public.set_report_card_comment(uuid, text, text) to authenticated;

create or replace function public.set_report_card_promotion(p_report_card_id uuid, p_status public.report_card_promotion)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_result public.report_cards;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then
    raise exception 'not_found: no report card %', p_report_card_id;
  end if;
  if not public.can_manage_academic(v_rc.school_id) then
    raise exception 'insufficient_privilege: only an academic manager may set promotion status';
  end if;
  if v_rc.status not in ('draft', 'teacher_review', 'hod_review') then
    raise exception 'report_card_locked: this report card is % and can no longer be edited', v_rc.status;
  end if;

  perform set_config('app.allow_report_card_write', 'true', true);
  update public.report_cards set promotion_status = p_status where id = p_report_card_id returning * into v_result;
  perform set_config('app.allow_report_card_write', 'false', true);
  perform public.write_audit_log(v_rc.school_id, auth.uid(), 'report_card_promotion_set', 'report_cards', p_report_card_id,
    jsonb_build_object('promotion_status', v_rc.promotion_status), jsonb_build_object('promotion_status', p_status));
  return v_result;
end;
$$;

revoke execute on function public.set_report_card_promotion(uuid, public.report_card_promotion) from public;
grant execute on function public.set_report_card_promotion(uuid, public.report_card_promotion) to authenticated;

-- Transition helper: performs one status move + timestamp/actor stamp +
-- audit, all under the write guard. Not granted to clients.
create or replace function public.report_card_transition_internal(
  p_report_card_id uuid, p_to public.report_card_status, p_action text, p_extra jsonb
) returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_result public.report_cards;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id for update;

  perform set_config('app.allow_report_card_write', 'true', true);
  update public.report_cards set
    status = p_to,
    submitted_at = case when p_to = 'teacher_review' and v_rc.submitted_at is null then now() else submitted_at end,
    submitted_by = case when p_to = 'teacher_review' and v_rc.submitted_by is null then auth.uid() else submitted_by end,
    reviewed_at = case when p_to = 'hod_review' then now() else reviewed_at end,
    reviewed_by = case when p_to = 'hod_review' then auth.uid() else reviewed_by end,
    approved_at = case when p_to = 'approved' then now() when p_to in ('teacher_review','hod_review','draft') then null else approved_at end,
    approved_by = case when p_to = 'approved' then auth.uid() when p_to in ('teacher_review','hod_review','draft') then null else approved_by end,
    locked_at   = case when p_to = 'approved' then now() when p_to in ('teacher_review','hod_review','draft') then null else locked_at end,
    published_at = case when p_to = 'published' then now() else published_at end,
    published_by = case when p_to = 'published' then auth.uid() else published_by end,
    archived_at = case when p_to = 'archived' then now() else archived_at end
  where id = p_report_card_id
  returning * into v_result;
  perform set_config('app.allow_report_card_write', 'false', true);

  perform public.write_audit_log(v_rc.school_id, auth.uid(), p_action, 'report_cards', p_report_card_id,
    jsonb_build_object('status', v_rc.status), jsonb_build_object('status', p_to) || coalesce(p_extra, '{}'::jsonb));
  return v_result;
end;
$$;

revoke execute on function public.report_card_transition_internal(uuid, public.report_card_status, text, jsonb) from public;

create or replace function public.submit_report_card(p_report_card_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare v_rc public.report_cards;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not public.can_manage_report_card(v_rc.school_id, v_rc.class_id) then
    raise exception 'insufficient_privilege: not permitted to submit this report card';
  end if;
  if v_rc.status <> 'draft' then
    raise exception 'invalid_state: only a draft report card can be submitted for review';
  end if;
  return public.report_card_transition_internal(p_report_card_id, 'teacher_review', 'report_card_submitted', null);
end;
$$;

revoke execute on function public.submit_report_card(uuid) from public;
grant execute on function public.submit_report_card(uuid) to authenticated;

create or replace function public.review_report_card(p_report_card_id uuid, p_approve boolean, p_note text default null)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not (public.can_manage_academic(v_rc.school_id) or v_role = 'department_head') then
    raise exception 'insufficient_privilege: only an HOD (department_head) or academic manager may review';
  end if;
  if v_rc.status <> 'teacher_review' then
    raise exception 'invalid_state: only a report card in teacher_review can be HOD-reviewed';
  end if;
  if p_approve then
    return public.report_card_transition_internal(p_report_card_id, 'hod_review', 'report_card_hod_approved', jsonb_build_object('note', p_note));
  else
    return public.report_card_transition_internal(p_report_card_id, 'draft', 'report_card_hod_returned', jsonb_build_object('note', p_note));
  end if;
end;
$$;

revoke execute on function public.review_report_card(uuid, boolean, text) from public;
grant execute on function public.review_report_card(uuid, boolean, text) to authenticated;

create or replace function public.approve_report_card(p_report_card_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_requires_hod boolean;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not public.can_manage_academic(v_rc.school_id) then
    raise exception 'insufficient_privilege: only a principal or school owner may approve report cards';
  end if;
  if v_rc.status not in ('teacher_review', 'hod_review') then
    raise exception 'invalid_state: only a report card in review can be approved';
  end if;
  select requires_hod_review into v_requires_hod from public.report_card_templates where id = v_rc.template_id;
  if v_requires_hod and v_rc.status <> 'hod_review' then
    raise exception 'invalid_state: this template requires HOD review before approval';
  end if;
  return public.report_card_transition_internal(p_report_card_id, 'approved', 'report_card_approved', null);
end;
$$;

revoke execute on function public.approve_report_card(uuid) from public;
grant execute on function public.approve_report_card(uuid) to authenticated;

create or replace function public.unapprove_report_card(p_report_card_id uuid, p_reason text)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare v_rc public.report_cards;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'invalid_argument: a reason is required to reopen an approved report card';
  end if;
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not public.can_manage_academic(v_rc.school_id) then
    raise exception 'insufficient_privilege: only a principal or school owner may reopen an approved report card';
  end if;
  if v_rc.status <> 'approved' then
    raise exception 'invalid_state: only an approved (not yet published) report card can be reopened';
  end if;
  return public.report_card_transition_internal(p_report_card_id, 'teacher_review', 'report_card_reopened', jsonb_build_object('reason', p_reason));
end;
$$;

revoke execute on function public.unapprove_report_card(uuid, text) from public;
grant execute on function public.unapprove_report_card(uuid, text) to authenticated;

create or replace function public.publish_report_card(p_report_card_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rc public.report_cards;
  v_result public.report_cards;
  v_guardian record;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not public.can_manage_academic(v_rc.school_id) then
    raise exception 'insufficient_privilege: only a principal or school owner may publish report cards';
  end if;
  if v_rc.status <> 'approved' then
    raise exception 'invalid_state: only an approved report card can be published';
  end if;

  v_result := public.report_card_transition_internal(p_report_card_id, 'published', 'report_card_published', null);

  for v_guardian in select guardian_profile_id from public.learner_guardians where learner_id = v_rc.learner_id
  loop
    perform public.create_notification(
      v_guardian.guardian_profile_id, 'report_card_published', 'Report card available',
      v_rc.learner_name || '''s report card is now available to view.',
      v_rc.school_id, 'report_cards', p_report_card_id, '/parent/children/' || v_rc.learner_id
    );
  end loop;

  return v_result;
end;
$$;

revoke execute on function public.publish_report_card(uuid) from public;
grant execute on function public.publish_report_card(uuid) to authenticated;

create or replace function public.archive_report_card(p_report_card_id uuid)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare v_rc public.report_cards;
begin
  select * into v_rc from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not public.can_manage_academic(v_rc.school_id) then
    raise exception 'insufficient_privilege: only a principal or school owner may archive report cards';
  end if;
  if v_rc.status <> 'published' then
    raise exception 'invalid_state: only a published report card can be archived';
  end if;
  return public.report_card_transition_internal(p_report_card_id, 'archived', 'report_card_archived', null);
end;
$$;

revoke execute on function public.archive_report_card(uuid) from public;
grant execute on function public.archive_report_card(uuid) to authenticated;

create or replace function public.reissue_report_card(p_report_card_id uuid, p_reason text)
returns public.report_cards
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.report_cards;
  v_new_id uuid;
  v_result public.report_cards;
begin
  if p_reason is null or char_length(trim(p_reason)) = 0 then
    raise exception 'invalid_argument: a reason is required to reissue a report card';
  end if;
  select * into v_old from public.report_cards where id = p_report_card_id;
  if not found then raise exception 'not_found: no report card %', p_report_card_id; end if;
  if not public.can_manage_academic(v_old.school_id) then
    raise exception 'insufficient_privilege: only a principal or school owner may reissue report cards';
  end if;
  if v_old.status not in ('published', 'archived') then
    raise exception 'invalid_state: only a published or archived report card can be reissued';
  end if;

  perform set_config('app.allow_report_card_write', 'true', true);

  -- Archive the old card FIRST — the one-live-card partial unique index
  -- (status <> 'archived') would otherwise reject the new draft while the
  -- old row is still published.
  update public.report_cards set status = 'archived', archived_at = now() where id = p_report_card_id;

  insert into public.report_cards (
    school_id, learner_id, academic_year_id, term_id, grade_id, class_id, template_id,
    version, status, learner_name, learner_number,
    class_teacher_comment, principal_comment, conduct_summary, promotion_status
  )
  select
    school_id, learner_id, academic_year_id, term_id, grade_id, class_id, template_id,
    v_old.version + 1, 'draft', learner_name, learner_number,
    class_teacher_comment, principal_comment, conduct_summary, promotion_status
  from public.report_cards where id = p_report_card_id
  returning id into v_new_id;

  insert into public.report_card_subjects (report_card_id, school_id, subject_id, subject_name, teacher_profile_id, teacher_name, weight, teacher_comment, sort_order)
  select v_new_id, school_id, subject_id, subject_name, teacher_profile_id, teacher_name, weight, teacher_comment, sort_order
  from public.report_card_subjects where report_card_id = p_report_card_id;

  update public.report_cards set superseded_by = v_new_id where id = p_report_card_id;

  perform set_config('app.allow_report_card_write', 'false', true);

  perform public.recalc_report_card_internal(v_new_id);

  perform public.write_audit_log(v_old.school_id, auth.uid(), 'report_card_reissued', 'report_cards', v_new_id,
    jsonb_build_object('superseded', p_report_card_id, 'old_version', v_old.version),
    jsonb_build_object('new_version', v_old.version + 1, 'reason', p_reason));

  select * into v_result from public.report_cards where id = v_new_id;
  return v_result;
end;
$$;

revoke execute on function public.reissue_report_card(uuid, text) from public;
grant execute on function public.reissue_report_card(uuid, text) to authenticated;

create or replace function public.publish_report_card_batch(p_batch_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.report_card_batches;
  v_rc uuid;
  v_count integer := 0;
begin
  select * into v_batch from public.report_card_batches where id = p_batch_id;
  if not found then raise exception 'not_found: no batch %', p_batch_id; end if;
  if not public.can_manage_academic(v_batch.school_id) then
    raise exception 'insufficient_privilege: only a principal or school owner may publish report cards';
  end if;

  for v_rc in select id from public.report_cards where batch_id = p_batch_id and status = 'approved'
  loop
    perform public.publish_report_card(v_rc);
    v_count := v_count + 1;
  end loop;

  perform public.write_audit_log(v_batch.school_id, auth.uid(), 'report_card_batch_published', 'report_card_batches', p_batch_id,
    null, jsonb_build_object('published', v_count));
  return v_count;
end;
$$;

revoke execute on function public.publish_report_card_batch(uuid) from public;
grant execute on function public.publish_report_card_batch(uuid) to authenticated;
