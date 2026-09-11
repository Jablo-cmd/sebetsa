-- Homework / Learning domain (1/1) — assignments, learner submissions, the
-- teacher review workflow, and parent/learner visibility.
--
-- DISTINCT FROM THE GRADEBOOK. `assessment_type` already has an
-- 'assignment' value, but `assessments` models a gradable EVENT (one row,
-- N marks) — it has no per-learner submission, no due date + late
-- tracking, no return-for-redo, no attachments a learner hands in. This
-- domain adds that workflow. Where a piece of homework is ALSO
-- gradebook-scored, `assignments.assessment_id` links the two and marking a
-- submission upserts the matching `assessment_results` row — reuse, not a
-- parallel grading system.
--
-- LEARNER SUBMISSION. Learner self-service login does not exist yet
-- (Domain 8). Today a submission is made by the learner's GUARDIAN on their
-- behalf (is_learner_guardian) — genuinely useful for primary school — and
-- the same RPCs already accept a learner acting for themselves
-- (learners.profile_id = auth.uid()), so Domain 8 inherits a working
-- submission path with no change here.
--
-- REUSE: class_teacher_assignments (per-class teacher scope, via
-- can_manage_homework mirroring can_manage_assessment), learner_enrollments
-- (who "assigned" rows are created for), academic_years / terms / classes /
-- subjects, the storage bucket pattern, is_learner_guardian,
-- can_view_academic, write_audit_log, create_notification.
--
-- SECURITY: every new tenant-scoped table is ENABLE + FORCE ROW LEVEL
-- SECURITY, fail-closed. Submission state (status / points / feedback /
-- returned_at) is RPC-only (assignment_submissions has no client write
-- policy + a protect trigger). Assignment status transitions go through
-- publish/close RPCs (assignments_protect trigger, app.allow_assignment_write
-- guard — same pattern as invoices / report_cards / admissions).

-- ===========================================================================
-- 0. Enums + helper
-- ===========================================================================

create type public.assignment_status as enum ('draft', 'published', 'closed');
create type public.assignment_submission_status as enum (
  'assigned', 'submitted', 'late', 'returned', 'reviewed', 'excused'
);

-- Is the caller the login account for this learner? (Domain 8 groundwork —
-- learners.profile_id. SECURITY DEFINER so a policy can call it without the
-- caller needing a learners SELECT grant for a not-yet-theirs row.)
create or replace function public.is_learner_self(p_learner_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.learners where id = p_learner_id and profile_id = auth.uid())
$$;
comment on function public.is_learner_self(uuid) is 'True when learners.profile_id = auth.uid() for p_learner_id. Guardian self-access is is_learner_guardian(); this is the learner-themselves counterpart, ready for the Learner Portal (Domain 8).';
grant execute on function public.is_learner_self(uuid) to authenticated;

-- Mirrors the app-level assessment.manage permission, scoped per class —
-- deliberately duplicated from can_manage_assessment() rather than called
-- across domains (same "duplicated logic, not duplicated risk" reasoning
-- that function's own comment documents).
create or replace function public.can_manage_homework(target_school_id uuid, target_class_id uuid)
returns boolean language sql stable set search_path = public as $$
  select
    public.can_manage_academic(target_school_id)
    or exists (
      select 1 from public.class_teacher_assignments cta
      where cta.class_id = target_class_id
        and cta.teacher_profile_id = auth.uid()
        and cta.active
    )
$$;
comment on function public.can_manage_homework(uuid, uuid) is 'Mirrors the app-level assessment.manage permission (ROLE_PERMISSIONS), scoped per class via class_teacher_assignments for teacher-variant roles. Keep in sync manually.';
grant execute on function public.can_manage_homework(uuid, uuid) to authenticated;

-- ===========================================================================
-- 1. assignments
-- ===========================================================================

create table public.assignments (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  term_id           uuid references public.terms (id),
  class_id          uuid not null references public.classes (id),
  subject_id        uuid not null references public.subjects (id),
  assessment_id     uuid references public.assessments (id) on delete set null,
  title             text not null check (char_length(title) > 0),
  instructions      text,
  due_at            timestamptz,
  max_points        integer check (max_points is null or max_points > 0),
  allow_resubmission boolean not null default false,
  status            public.assignment_status not null default 'draft',
  rubric            jsonb not null default '[]'::jsonb,
  published_at      timestamptz,
  closed_at         timestamptz,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint assignments_rubric_is_array check (jsonb_typeof(rubric) = 'array')
);

comment on table public.assignments is 'A piece of homework for one class + subject. status draft -> published (fans out an "assigned" assignment_submissions row per actively-enrolled learner) -> closed. assessment_id links it to a gradebook assessment when the work is also formally scored. status / published_at / closed_at are RPC-only (assignments_protect).';
comment on column public.assignments.rubric is 'Optional marking guide: a JSON array of { "criterion": text, "points": number }. Submissions store rubric_scores keyed by criterion.';

create index assignments_school_id_idx on public.assignments (school_id);
create index assignments_class_subject_idx on public.assignments (class_id, subject_id);
create index assignments_academic_year_idx on public.assignments (academic_year_id);
create index assignments_status_due_idx on public.assignments (school_id, status, due_at);
create index assignments_assessment_id_idx on public.assignments (assessment_id) where assessment_id is not null;

create trigger assignments_set_updated_at
  before update on public.assignments for each row execute function public.set_updated_at();
create trigger assignments_set_created_updated_by
  before insert or update on public.assignments for each row execute function public.set_created_updated_by();

create or replace function public.assignments_validate_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_s uuid; v_year uuid;
begin
  select school_id into v_s from public.academic_years where id = new.academic_year_id;
  if v_s is distinct from new.school_id then raise exception 'insufficient_privilege: academic_year_id must belong to the same school'; end if;
  if new.term_id is not null then
    select school_id, academic_year_id into v_s, v_year from public.terms where id = new.term_id;
    if v_s is distinct from new.school_id then raise exception 'insufficient_privilege: term_id must belong to the same school'; end if;
    if v_year is distinct from new.academic_year_id then raise exception 'insufficient_privilege: term_id must belong to the same academic year'; end if;
  end if;
  select school_id into v_s from public.classes where id = new.class_id;
  if v_s is distinct from new.school_id then raise exception 'insufficient_privilege: class_id must belong to the same school'; end if;
  select school_id into v_s from public.subjects where id = new.subject_id;
  if v_s is distinct from new.school_id then raise exception 'insufficient_privilege: subject_id must belong to the same school'; end if;
  if new.assessment_id is not null then
    select school_id into v_s from public.assessments where id = new.assessment_id;
    if v_s is distinct from new.school_id then raise exception 'insufficient_privilege: assessment_id must belong to the same school'; end if;
  end if;
  return new;
end;
$$;
create trigger assignments_validate_tenant_trigger
  before insert or update on public.assignments for each row execute function public.assignments_validate_tenant();

create or replace function public.assignments_protect()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('app.allow_assignment_write', true), '') = 'true' then
    return new;
  end if;
  if tg_op = 'UPDATE' and (
       new.status is distinct from old.status
    or new.published_at is distinct from old.published_at
    or new.closed_at is distinct from old.closed_at
  ) then
    raise exception 'insufficient_privilege: assignment status is changed only through publish_assignment() / close_assignment()';
  end if;
  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception 'insufficient_privilege: an assignment is created as a draft';
  end if;
  return new;
end;
$$;
create trigger assignments_protect_trigger
  before insert or update on public.assignments for each row execute function public.assignments_protect();

-- ===========================================================================
-- 2. assignment_resources — teacher-attached files / links
-- ===========================================================================

create table public.assignment_resources (
  id             uuid primary key default gen_random_uuid(),
  assignment_id  uuid not null references public.assignments (id) on delete cascade,
  school_id      uuid not null references public.schools (id) on delete cascade,
  label          text not null check (char_length(label) > 0),
  url            text,
  storage_path   text,
  mime_type      text,
  size_bytes     integer,
  created_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  constraint assignment_resources_has_target check (url is not null or storage_path is not null)
);

comment on table public.assignment_resources is 'A link or file attached to an assignment by staff (a worksheet, a reference URL). Files live in the private assignment-files bucket.';

create index assignment_resources_assignment_idx on public.assignment_resources (assignment_id);

-- ===========================================================================
-- 3. assignment_submissions — one row per (assignment, learner)
-- ===========================================================================

create table public.assignment_submissions (
  id               uuid primary key default gen_random_uuid(),
  assignment_id    uuid not null references public.assignments (id) on delete cascade,
  school_id        uuid not null references public.schools (id) on delete cascade,
  learner_id       uuid not null references public.learners (id) on delete cascade,
  status           public.assignment_submission_status not null default 'assigned',
  submission_text  text,
  submitted_at     timestamptz,
  submitted_by     uuid references public.profiles (id) on delete set null,
  is_late          boolean not null default false,
  attempt_count    integer not null default 0,
  points_awarded   integer check (points_awarded is null or points_awarded >= 0),
  rubric_scores    jsonb not null default '{}'::jsonb,
  teacher_feedback text,
  marked_by        uuid references public.profiles (id) on delete set null,
  marked_at        timestamptz,
  returned_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint assignment_submissions_rubric_scores_is_object check (jsonb_typeof(rubric_scores) = 'object')
);

comment on table public.assignment_submissions is 'One learner''s state for one assignment. Created as ''assigned'' by publish_assignment() for every enrolled learner. status: assigned -> submitted|late (submit_assignment) -> returned (return_assignment_submission, redo allowed if the assignment allows resubmission) or reviewed (mark_assignment_submission, final). All state is RPC-only.';

create unique index assignment_submissions_unique_idx on public.assignment_submissions (assignment_id, learner_id);
create index assignment_submissions_school_id_idx on public.assignment_submissions (school_id);
create index assignment_submissions_learner_idx on public.assignment_submissions (learner_id);
create index assignment_submissions_status_idx on public.assignment_submissions (assignment_id, status);

create trigger assignment_submissions_set_updated_at
  before update on public.assignment_submissions for each row execute function public.set_updated_at();

create or replace function public.assignment_submissions_protect()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('app.allow_submission_write', true), '') <> 'true' then
    raise exception 'insufficient_privilege: assignment submissions are written only through the homework workflow functions';
  end if;
  return new;
end;
$$;
create trigger assignment_submissions_protect_trigger
  before insert or update on public.assignment_submissions for each row execute function public.assignment_submissions_protect();

-- ===========================================================================
-- 4. assignment_submission_files — learner-attached hand-ins
-- ===========================================================================

create table public.assignment_submission_files (
  id             uuid primary key default gen_random_uuid(),
  submission_id  uuid not null references public.assignment_submissions (id) on delete cascade,
  assignment_id  uuid not null references public.assignments (id) on delete cascade,
  school_id      uuid not null references public.schools (id) on delete cascade,
  learner_id     uuid not null references public.learners (id) on delete cascade,
  label          text not null check (char_length(label) > 0),
  storage_path   text not null,
  mime_type      text,
  size_bytes     integer,
  uploaded_by    uuid references public.profiles (id) on delete set null,
  uploaded_at    timestamptz not null default now()
);

comment on table public.assignment_submission_files is 'A file a learner (or their guardian) handed in for a submission. In the private assignment-files bucket, path <school_id>/<assignment_id>/<submission_id>/<file>. Registered by register_submission_file() after upload.';

create index assignment_submission_files_submission_idx on public.assignment_submission_files (submission_id);

-- ===========================================================================
-- 4b. Helper functions that reference the tables above
-- ===========================================================================

create or replace function public.can_manage_homework_submission(p_assignment_id uuid)
returns boolean language sql stable set search_path = public as $$
  select public.can_manage_homework(school_id, class_id)
  from public.assignments where id = p_assignment_id
$$;
grant execute on function public.can_manage_homework_submission(uuid) to authenticated;

-- Internal in-app notify helpers.
create or replace function public.homework_notify_guardians(
  p_assignment_id uuid, p_type text, p_title text, p_body text
) returns void language plpgsql security definer set search_path = public as $$
declare v_a record; v_g record;
begin
  select school_id, title into v_a from public.assignments where id = p_assignment_id;
  if not found then return; end if;
  for v_g in
    select distinct lg.guardian_profile_id
    from public.assignment_submissions s
    join public.learner_guardians lg on lg.learner_id = s.learner_id and lg.active
    where s.assignment_id = p_assignment_id
  loop
    perform public.create_notification(
      v_g.guardian_profile_id, p_type, p_title, left(p_body, 280),
      v_a.school_id, 'assignments', p_assignment_id,
      '/parent/homework/' || p_assignment_id::text
    );
  end loop;
end;
$$;
revoke execute on function public.homework_notify_guardians(uuid, text, text, text) from public;

create or replace function public.create_notification_for_submission_guardians(
  p_learner_id uuid, p_school_id uuid, p_assignment_id uuid, p_type text, p_title text, p_body text
) returns void language plpgsql security definer set search_path = public as $$
declare v_g record;
begin
  for v_g in select guardian_profile_id from public.learner_guardians where learner_id = p_learner_id and active
  loop
    perform public.create_notification(v_g.guardian_profile_id, p_type, p_title, left(p_body, 280),
      p_school_id, 'assignments', p_assignment_id, '/parent/homework/' || p_assignment_id::text);
  end loop;
end;
$$;
revoke execute on function public.create_notification_for_submission_guardians(uuid, uuid, uuid, text, text, text) from public;

-- ===========================================================================
-- 5. RLS
-- ===========================================================================

alter table public.assignments enable row level security;
alter table public.assignments force row level security;
alter table public.assignment_resources enable row level security;
alter table public.assignment_resources force row level security;
alter table public.assignment_submissions enable row level security;
alter table public.assignment_submissions force row level security;
alter table public.assignment_submission_files enable row level security;
alter table public.assignment_submission_files force row level security;

-- assignments: staff who can view academics see all; a guardian/learner
-- sees a PUBLISHED assignment only if their linked learner has a submission
-- row for it (same shape as assessments_select_for_guardians).
create policy assignments_select on public.assignments
  for select to authenticated using (
    public.can_view_academic(school_id)
    or public.is_platform_admin()
    or (status <> 'draft' and exists (
      select 1 from public.assignment_submissions s
      where s.assignment_id = assignments.id
        and (public.is_learner_guardian(s.learner_id) or public.is_learner_self(s.learner_id))
    ))
  );
create policy assignments_insert on public.assignments
  for insert to authenticated with check (public.can_manage_homework(school_id, class_id) and status = 'draft');
create policy assignments_update on public.assignments
  for update to authenticated using (public.can_manage_homework(school_id, class_id)) with check (public.can_manage_homework(school_id, class_id));

create policy assignment_resources_select on public.assignment_resources
  for select to authenticated using (
    public.can_view_academic(school_id)
    or public.is_platform_admin()
    or exists (
      select 1 from public.assignments a
      join public.assignment_submissions s on s.assignment_id = a.id
      where a.id = assignment_resources.assignment_id and a.status <> 'draft'
        and (public.is_learner_guardian(s.learner_id) or public.is_learner_self(s.learner_id))
    )
  );
create policy assignment_resources_insert on public.assignment_resources
  for insert to authenticated with check (public.can_manage_homework_submission(assignment_id));
create policy assignment_resources_update on public.assignment_resources
  for update to authenticated
  using (public.can_manage_homework_submission(assignment_id))
  with check (public.can_manage_homework_submission(assignment_id));

-- submissions: staff (academic view), plus the learner's guardian / the
-- learner themselves. No client write — RPCs only (protect trigger backstop).
create policy assignment_submissions_select on public.assignment_submissions
  for select to authenticated using (
    public.can_view_academic(school_id)
    or public.is_platform_admin()
    or public.is_learner_guardian(learner_id)
    or public.is_learner_self(learner_id)
  );

create policy assignment_submission_files_select on public.assignment_submission_files
  for select to authenticated using (
    public.can_view_academic(school_id)
    or public.is_platform_admin()
    or public.is_learner_guardian(learner_id)
    or public.is_learner_self(learner_id)
  );

-- ===========================================================================
-- 6. Workflow RPCs
-- ===========================================================================

create or replace function public.create_assignment(
  p_school_id uuid,
  p_class_id uuid,
  p_subject_id uuid,
  p_academic_year_id uuid,
  p_title text,
  p_instructions text default null,
  p_due_at timestamptz default null,
  p_max_points integer default null,
  p_term_id uuid default null,
  p_allow_resubmission boolean default false,
  p_rubric jsonb default '[]'::jsonb,
  p_assessment_id uuid default null
) returns public.assignments
language plpgsql security definer set search_path = public as $$
declare v_row public.assignments;
begin
  if not public.can_manage_homework(p_school_id, p_class_id) then
    raise exception 'insufficient_privilege: cannot manage homework for this class';
  end if;
  insert into public.assignments (
    school_id, class_id, subject_id, academic_year_id, term_id, title, instructions,
    due_at, max_points, allow_resubmission, rubric, assessment_id
  ) values (
    p_school_id, p_class_id, p_subject_id, p_academic_year_id, p_term_id, p_title, p_instructions,
    p_due_at, p_max_points, coalesce(p_allow_resubmission, false), coalesce(p_rubric, '[]'::jsonb), p_assessment_id
  ) returning * into v_row;
  perform public.write_audit_log(p_school_id, auth.uid(), 'assignment_created', 'assignments', v_row.id, null,
    jsonb_build_object('title', p_title, 'class_id', p_class_id));
  return v_row;
end;
$$;
revoke execute on function public.create_assignment(uuid, uuid, uuid, uuid, text, text, timestamptz, integer, uuid, boolean, jsonb, uuid) from public;
grant execute on function public.create_assignment(uuid, uuid, uuid, uuid, text, text, timestamptz, integer, uuid, boolean, jsonb, uuid) to authenticated;

create or replace function public.publish_assignment(p_assignment_id uuid)
returns public.assignments
language plpgsql security definer set search_path = public as $$
declare v_a public.assignments; v_row public.assignments; v_created int := 0;
begin
  select * into v_a from public.assignments where id = p_assignment_id for update;
  if not found then raise exception 'not_found: no assignment %', p_assignment_id; end if;
  if not public.can_manage_homework(v_a.school_id, v_a.class_id) then
    raise exception 'insufficient_privilege: cannot manage homework for this class';
  end if;
  if v_a.status <> 'draft' then raise exception 'invalid_state: only a draft assignment can be published'; end if;

  perform set_config('app.allow_assignment_write', 'true', true);
  update public.assignments set status = 'published', published_at = now() where id = p_assignment_id returning * into v_row;
  perform set_config('app.allow_assignment_write', 'false', true);

  -- One 'assigned' submission per actively-enrolled learner in the class.
  perform set_config('app.allow_submission_write', 'true', true);
  insert into public.assignment_submissions (assignment_id, school_id, learner_id)
  select p_assignment_id, v_a.school_id, e.learner_id
  from public.learner_enrollments e
  where e.class_id = v_a.class_id
    and e.academic_year_id = v_a.academic_year_id
    and e.enrollment_status = 'enrolled'
  on conflict (assignment_id, learner_id) do nothing;
  get diagnostics v_created = row_count;
  perform set_config('app.allow_submission_write', 'false', true);

  perform public.write_audit_log(v_a.school_id, auth.uid(), 'assignment_published', 'assignments', p_assignment_id, null,
    jsonb_build_object('assigned_count', v_created));

  -- Notify each learner's guardians (in-app; delivery fan-out handles the rest).
  perform public.homework_notify_guardians(p_assignment_id, 'assignment_published',
    'New homework: ' || v_a.title,
    coalesce(nullif(trim(v_a.instructions), ''), 'A new assignment has been set.'));

  return v_row;
end;
$$;
revoke execute on function public.publish_assignment(uuid) from public;
grant execute on function public.publish_assignment(uuid) to authenticated;

create or replace function public.close_assignment(p_assignment_id uuid)
returns public.assignments
language plpgsql security definer set search_path = public as $$
declare v_a public.assignments; v_row public.assignments;
begin
  select * into v_a from public.assignments where id = p_assignment_id for update;
  if not found then raise exception 'not_found: no assignment %', p_assignment_id; end if;
  if not public.can_manage_homework(v_a.school_id, v_a.class_id) then
    raise exception 'insufficient_privilege: cannot manage homework for this class';
  end if;
  if v_a.status <> 'published' then raise exception 'invalid_state: only a published assignment can be closed'; end if;
  perform set_config('app.allow_assignment_write', 'true', true);
  update public.assignments set status = 'closed', closed_at = now() where id = p_assignment_id returning * into v_row;
  perform set_config('app.allow_assignment_write', 'false', true);
  perform public.write_audit_log(v_a.school_id, auth.uid(), 'assignment_closed', 'assignments', p_assignment_id, null, null);
  return v_row;
end;
$$;
revoke execute on function public.close_assignment(uuid) from public;
grant execute on function public.close_assignment(uuid) to authenticated;

create or replace function public.submit_assignment(
  p_assignment_id uuid, p_learner_id uuid, p_submission_text text default null
) returns public.assignment_submissions
language plpgsql security definer set search_path = public as $$
declare v_a public.assignments; v_sub public.assignment_submissions; v_late boolean; v_new_status public.assignment_submission_status;
begin
  select * into v_a from public.assignments where id = p_assignment_id;
  if not found then raise exception 'not_found: no assignment %', p_assignment_id; end if;
  if v_a.status = 'draft' then raise exception 'invalid_state: this assignment is not open for submission'; end if;

  if not (public.is_learner_self(p_learner_id) or public.is_learner_guardian(p_learner_id)
          or public.can_manage_homework(v_a.school_id, v_a.class_id)) then
    raise exception 'insufficient_privilege: you cannot submit for this learner';
  end if;

  select * into v_sub from public.assignment_submissions
    where assignment_id = p_assignment_id and learner_id = p_learner_id for update;
  if not found then raise exception 'not_found: this learner is not on this assignment'; end if;

  if v_sub.status in ('submitted', 'late', 'reviewed') and not v_a.allow_resubmission then
    raise exception 'invalid_state: this assignment does not allow resubmission';
  end if;
  if v_sub.status = 'reviewed' then
    raise exception 'invalid_state: this submission has been finalised';
  end if;

  v_late := v_a.due_at is not null and now() > v_a.due_at;
  v_new_status := case when v_late then 'late' else 'submitted' end;

  perform set_config('app.allow_submission_write', 'true', true);
  update public.assignment_submissions set
    status = v_new_status,
    submission_text = p_submission_text,
    submitted_at = now(),
    submitted_by = auth.uid(),
    is_late = v_late,
    attempt_count = attempt_count + 1,
    returned_at = null
    where id = v_sub.id returning * into v_sub;
  perform set_config('app.allow_submission_write', 'false', true);

  perform public.write_audit_log(v_a.school_id, auth.uid(), 'assignment_submitted', 'assignment_submissions', v_sub.id, null,
    jsonb_build_object('assignment_id', p_assignment_id, 'learner_id', p_learner_id, 'late', v_late));
  return v_sub;
end;
$$;
revoke execute on function public.submit_assignment(uuid, uuid, text) from public;
grant execute on function public.submit_assignment(uuid, uuid, text) to authenticated;

create or replace function public.mark_assignment_submission(
  p_submission_id uuid,
  p_points integer default null,
  p_feedback text default null,
  p_rubric_scores jsonb default null,
  p_finalise boolean default true
) returns public.assignment_submissions
language plpgsql security definer set search_path = public as $$
declare v_sub public.assignment_submissions; v_a public.assignments;
begin
  select * into v_sub from public.assignment_submissions where id = p_submission_id for update;
  if not found then raise exception 'not_found: no submission %', p_submission_id; end if;
  select * into v_a from public.assignments where id = v_sub.assignment_id;
  if not public.can_manage_homework(v_a.school_id, v_a.class_id) then
    raise exception 'insufficient_privilege: cannot mark homework for this class';
  end if;
  if p_points is not null and v_a.max_points is not null and p_points > v_a.max_points then
    raise exception 'invalid_argument: points cannot exceed the assignment maximum (%).', v_a.max_points;
  end if;

  perform set_config('app.allow_submission_write', 'true', true);
  update public.assignment_submissions set
    points_awarded = coalesce(p_points, points_awarded),
    teacher_feedback = coalesce(p_feedback, teacher_feedback),
    rubric_scores = coalesce(p_rubric_scores, rubric_scores),
    marked_by = auth.uid(),
    marked_at = now(),
    returned_at = now(),
    status = case when p_finalise then 'reviewed'::public.assignment_submission_status
                  else 'returned'::public.assignment_submission_status end
    where id = p_submission_id returning * into v_sub;
  perform set_config('app.allow_submission_write', 'false', true);

  -- Gradebook sync: if this assignment is linked to an assessment and a
  -- mark was given, upsert the matching assessment_results row.
  if v_a.assessment_id is not null and v_sub.points_awarded is not null then
    insert into public.assessment_results (school_id, assessment_id, learner_id, mark)
    values (v_a.school_id, v_a.assessment_id, v_sub.learner_id, v_sub.points_awarded)
    on conflict (assessment_id, learner_id) do update set mark = excluded.mark, updated_by = auth.uid();
  end if;

  perform public.write_audit_log(v_a.school_id, auth.uid(), 'assignment_marked', 'assignment_submissions', p_submission_id, null,
    jsonb_build_object('points', v_sub.points_awarded, 'finalised', p_finalise));

  -- Notify the learner's guardians that work was returned.
  perform public.create_notification_for_submission_guardians(
    v_sub.learner_id, v_a.school_id, v_a.id,
    case when p_finalise then 'assignment_reviewed' else 'assignment_returned' end,
    case when p_finalise then 'Homework marked: ' || v_a.title else 'Homework returned: ' || v_a.title end,
    coalesce(nullif(trim(p_feedback), ''), 'Your teacher has reviewed this assignment.'));
  return v_sub;
end;
$$;
revoke execute on function public.mark_assignment_submission(uuid, integer, text, jsonb, boolean) from public;
grant execute on function public.mark_assignment_submission(uuid, integer, text, jsonb, boolean) to authenticated;

create or replace function public.excuse_assignment_submission(p_submission_id uuid, p_reason text default null)
returns public.assignment_submissions
language plpgsql security definer set search_path = public as $$
declare v_sub public.assignment_submissions; v_a public.assignments;
begin
  select * into v_sub from public.assignment_submissions where id = p_submission_id for update;
  if not found then raise exception 'not_found: no submission %', p_submission_id; end if;
  select * into v_a from public.assignments where id = v_sub.assignment_id;
  if not public.can_manage_homework(v_a.school_id, v_a.class_id) then
    raise exception 'insufficient_privilege: cannot manage homework for this class';
  end if;
  perform set_config('app.allow_submission_write', 'true', true);
  update public.assignment_submissions set status = 'excused', teacher_feedback = coalesce(p_reason, teacher_feedback), marked_by = auth.uid(), marked_at = now()
    where id = p_submission_id returning * into v_sub;
  perform set_config('app.allow_submission_write', 'false', true);
  perform public.write_audit_log(v_a.school_id, auth.uid(), 'assignment_excused', 'assignment_submissions', p_submission_id, null, null);
  return v_sub;
end;
$$;
revoke execute on function public.excuse_assignment_submission(uuid, text) from public;
grant execute on function public.excuse_assignment_submission(uuid, text) to authenticated;

create or replace function public.register_assignment_resource(
  p_assignment_id uuid, p_label text, p_url text default null, p_storage_path text default null,
  p_mime_type text default null, p_size_bytes integer default null
) returns public.assignment_resources
language plpgsql security definer set search_path = public as $$
declare v_a public.assignments; v_row public.assignment_resources;
begin
  select * into v_a from public.assignments where id = p_assignment_id;
  if not found then raise exception 'not_found: no assignment %', p_assignment_id; end if;
  if not public.can_manage_homework(v_a.school_id, v_a.class_id) then
    raise exception 'insufficient_privilege: cannot manage homework for this class';
  end if;
  if p_url is null and p_storage_path is null then raise exception 'invalid_argument: a url or a file is required'; end if;
  insert into public.assignment_resources (assignment_id, school_id, label, url, storage_path, mime_type, size_bytes, created_by)
  values (p_assignment_id, v_a.school_id, p_label, p_url, p_storage_path, p_mime_type, p_size_bytes, auth.uid())
  returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.register_assignment_resource(uuid, text, text, text, text, integer) from public;
grant execute on function public.register_assignment_resource(uuid, text, text, text, text, integer) to authenticated;

create or replace function public.register_submission_file(
  p_submission_id uuid, p_label text, p_storage_path text, p_mime_type text default null, p_size_bytes integer default null
) returns public.assignment_submission_files
language plpgsql security definer set search_path = public as $$
declare v_sub public.assignment_submissions; v_a public.assignments; v_row public.assignment_submission_files;
begin
  select * into v_sub from public.assignment_submissions where id = p_submission_id;
  if not found then raise exception 'not_found: no submission %', p_submission_id; end if;
  select * into v_a from public.assignments where id = v_sub.assignment_id;
  if not (public.is_learner_self(v_sub.learner_id) or public.is_learner_guardian(v_sub.learner_id)
          or public.can_manage_homework(v_a.school_id, v_a.class_id)) then
    raise exception 'insufficient_privilege: you cannot attach a file to this submission';
  end if;
  if p_label is null or char_length(trim(p_label)) = 0 then raise exception 'invalid_argument: label is required'; end if;
  insert into public.assignment_submission_files (submission_id, assignment_id, school_id, learner_id, label, storage_path, mime_type, size_bytes, uploaded_by)
  values (p_submission_id, v_sub.assignment_id, v_sub.school_id, v_sub.learner_id, trim(p_label), p_storage_path, p_mime_type, p_size_bytes, auth.uid())
  returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.register_submission_file(uuid, text, text, text, integer) from public;
grant execute on function public.register_submission_file(uuid, text, text, text, integer) to authenticated;

-- ===========================================================================
-- 7. Private storage bucket
-- ===========================================================================

insert into storage.buckets (id, name, public)
values ('assignment-files', 'assignment-files', false)
on conflict (id) do nothing;

-- Path: <school_id>/<assignment_id>/[<submission_id>/]<file>. Staff who can
-- view academics for the school read everything; a guardian/learner reads a
-- file only if it is registered against their own learner's submission (or
-- a resource on a non-draft assignment their learner is on). Writes go
-- through the register_* RPCs, which hold the real authorization — the
-- client uploads the object first, so the write policy only pins the tenant
-- path (an unregistered upload is an inert orphan).
create policy assignment_files_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'assignment-files'
    and (
      public.can_view_academic((storage.foldername(name))[1]::uuid)
      or exists (
        select 1 from public.assignment_submission_files f
        where f.storage_path = storage.objects.name
          and (public.is_learner_guardian(f.learner_id) or public.is_learner_self(f.learner_id))
      )
      or exists (
        select 1 from public.assignment_resources r
        join public.assignment_submissions s on s.assignment_id = r.assignment_id
        where r.storage_path = storage.objects.name
          and (public.is_learner_guardian(s.learner_id) or public.is_learner_self(s.learner_id))
      )
    )
  );
create policy assignment_files_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'assignment-files'
    and (storage.foldername(name))[1]::uuid = public.current_tenant_id()
  );
