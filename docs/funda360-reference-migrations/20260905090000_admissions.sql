-- Admissions domain (1/1) — the application entity, its workflow, document
-- requirements, and conversion to a learner + guardian + enrolment.
--
-- RECONCILES the pre-existing internal "Admissions Pipeline" (a Kanban over
-- learners.status prospective→applied→accepted→enrolled). That board moved
-- learner records that ALREADY EXISTED; it did not model an application
-- from a family who is not yet in the system. This migration inverts that:
-- an `admission_applications` row is created FIRST (by staff, or by the
-- public intake Edge Function), worked through a full review workflow, and
-- only on acceptance does convert_admission_application() create the
-- learner / guardian / enrolment. The learners.status enum and its
-- forward-only transition whitelist (20260803190000) are UNCHANGED — a
-- converted applicant's learner record still enters at 'accepted' and is
-- promoted to 'active' by the normal learner lifecycle. The old board UI
-- and its learner-status-based hook are removed by this domain's frontend
-- change; the enum is not.
--
-- PUBLIC INTAKE: a prospective family has no account (auth is
-- invitation-only in this system). They submit through a public form
-- served by the `admissions-public` Edge Function, which is the single
-- controlled entry point (service_role) — there is NO anon RLS policy on
-- any table here. The function calls the public_* RPCs below (granted to
-- service_role only). Resume is by email + reference number.
--
-- SECURITY: every new tenant-scoped table is ENABLE + FORCE ROW LEVEL
-- SECURITY, fail-closed. admission_applications status / reference /
-- decision / converted_learner_id columns are RPC-only (protect trigger,
-- same app.allow_* guard pattern as invoices / report_cards). Staff may
-- edit the free-text application data while it is still pre-decision.

create type public.admission_application_status as enum (
  'draft', 'submitted', 'under_review', 'incomplete',
  'interview_required', 'assessment_required', 'waitlisted',
  'accepted', 'rejected', 'withdrawn', 'enrolled'
);

-- ---------------------------------------------------------------------------
-- 1. Per-school reference-number counter (gap-free). RPC-only, no RLS policy.

create table public.admission_counters (
  school_id   uuid primary key references public.schools (id) on delete cascade,
  next_value  bigint not null default 1 check (next_value >= 1)
);

alter table public.admission_counters enable row level security;
alter table public.admission_counters force row level security;

create or replace function public.next_admission_reference(p_school_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next bigint;
  v_year text := to_char(now() at time zone 'Africa/Johannesburg', 'YYYY');
begin
  insert into public.admission_counters (school_id, next_value) values (p_school_id, 1)
  on conflict (school_id) do nothing;
  update public.admission_counters set next_value = next_value + 1
    where school_id = p_school_id
    returning next_value - 1 into v_next;
  return 'APP-' || v_year || '-' || lpad(v_next::text, 5, '0');
end;
$$;

revoke execute on function public.next_admission_reference(uuid) from public;
revoke execute on function public.next_admission_reference(uuid) from authenticated;

-- ---------------------------------------------------------------------------
-- 2. admission_document_requirements — configurable per school (+ grade).

create table public.admission_document_requirements (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  grade_id     uuid references public.grades (id),
  label        text not null check (char_length(label) > 0),
  description  text,
  required     boolean not null default true,
  active       boolean not null default true,
  sort_order   integer not null default 0,
  created_by   uuid references public.profiles (id) on delete set null,
  updated_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.admission_document_requirements is 'What documents an application must include. grade_id NULL = applies to any grade; set = only that grade. Never hard-deleted — active=false is the archive state.';

create index admission_document_requirements_school_id_idx on public.admission_document_requirements (school_id);
create index admission_document_requirements_grade_id_idx on public.admission_document_requirements (grade_id);

create trigger admission_document_requirements_set_updated_at
  before update on public.admission_document_requirements
  for each row execute function public.set_updated_at();
create trigger admission_document_requirements_set_created_updated_by
  before insert or update on public.admission_document_requirements
  for each row execute function public.set_created_updated_by();

create or replace function public.admission_document_requirements_validate()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_grade_school uuid;
begin
  if new.grade_id is not null then
    select school_id into v_grade_school from public.grades where id = new.grade_id;
    if v_grade_school is distinct from new.school_id then
      raise exception 'insufficient_privilege: grade_id must belong to the same school';
    end if;
  end if;
  return new;
end;
$$;
create trigger admission_document_requirements_validate_trigger
  before insert or update on public.admission_document_requirements
  for each row execute function public.admission_document_requirements_validate();

-- ---------------------------------------------------------------------------
-- 3. admission_applications.

create table public.admission_applications (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid not null references public.schools (id) on delete cascade,
  academic_year_id      uuid references public.academic_years (id),
  requested_grade_id    uuid references public.grades (id),
  reference_number      text,
  status                public.admission_application_status not null default 'draft',
  resume_token          uuid not null default gen_random_uuid(),

  applicant_first_name  text,
  applicant_last_name   text,
  applicant_email       text not null check (applicant_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  applicant_phone       text,
  applicant_relationship text,

  learner_first_name    text,
  learner_last_name     text,
  learner_date_of_birth date,
  learner_gender        text,
  learner_id_number     text,
  learner_nationality   text,
  learner_home_language text,
  prior_school          text,
  additional_notes      text,

  interview_at          timestamptz,
  assessment_at         timestamptz,
  decision_at           timestamptz,
  decision_by           uuid references public.profiles (id) on delete set null,
  decision_reason       text,

  converted_learner_id  uuid references public.learners (id) on delete set null,
  submitted_at          timestamptz,
  is_public_submission  boolean not null default false,

  created_by            uuid references public.profiles (id) on delete set null,
  updated_by            uuid references public.profiles (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint admission_applications_submitted_has_reference
    check (status = 'draft' or reference_number is not null)
);

comment on table public.admission_applications is 'One family''s application to enrol one learner. Created by staff (create_admission_application) or by the public intake Edge Function. status / reference_number / decision_* / converted_learner_id are RPC-only (admission_applications_protect). Free-text application data is staff-editable while status is pre-decision (draft/submitted/under_review/incomplete). Never hard-deleted.';
comment on column public.admission_applications.resume_token is 'Secret handed to a public applicant so they can resume an unsubmitted application. Not a login — only ever accepted by the public_* RPCs, which additionally scope by status.';

create unique index admission_applications_school_reference_key on public.admission_applications (school_id, reference_number) where reference_number is not null;
create unique index admission_applications_resume_token_key on public.admission_applications (resume_token);
create index admission_applications_school_status_idx on public.admission_applications (school_id, status);
create index admission_applications_school_year_idx on public.admission_applications (school_id, academic_year_id);
create index admission_applications_grade_idx on public.admission_applications (requested_grade_id);
create index admission_applications_email_idx on public.admission_applications (lower(applicant_email));
create index admission_applications_converted_learner_idx on public.admission_applications (converted_learner_id);

create trigger admission_applications_set_updated_at
  before update on public.admission_applications
  for each row execute function public.set_updated_at();
create trigger admission_applications_set_created_updated_by
  before insert or update on public.admission_applications
  for each row execute function public.set_created_updated_by();

create or replace function public.admission_applications_validate_tenant()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_school uuid;
begin
  if new.academic_year_id is not null then
    select school_id into v_school from public.academic_years where id = new.academic_year_id;
    if v_school is distinct from new.school_id then
      raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
    end if;
  end if;
  if new.requested_grade_id is not null then
    select school_id into v_school from public.grades where id = new.requested_grade_id;
    if v_school is distinct from new.school_id then
      raise exception 'insufficient_privilege: requested_grade_id must belong to the same school';
    end if;
  end if;
  return new;
end;
$$;
create trigger admission_applications_validate_tenant_trigger
  before insert or update on public.admission_applications
  for each row execute function public.admission_applications_validate_tenant();

-- status / reference / decision / conversion columns move only through the
-- workflow RPCs (which set app.allow_admission_write).
create or replace function public.admission_applications_protect()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('app.allow_admission_write', true), '') = 'true' then
    return new;
  end if;
  if tg_op = 'UPDATE' and (
       new.status is distinct from old.status
    or new.reference_number is distinct from old.reference_number
    or new.decision_at is distinct from old.decision_at
    or new.decision_by is distinct from old.decision_by
    or new.decision_reason is distinct from old.decision_reason
    or new.converted_learner_id is distinct from old.converted_learner_id
    or new.submitted_at is distinct from old.submitted_at
    or new.resume_token is distinct from old.resume_token
  ) then
    raise exception 'insufficient_privilege: application status / reference / decision are changed only through the admissions workflow functions';
  end if;
  if tg_op = 'UPDATE' and old.status in ('accepted', 'rejected', 'withdrawn', 'enrolled')
     and (new.applicant_email is distinct from old.applicant_email
       or new.learner_first_name is distinct from old.learner_first_name
       or new.learner_last_name is distinct from old.learner_last_name) then
    raise exception 'application_locked: a decided application''s core details cannot be edited';
  end if;
  if tg_op = 'INSERT' and new.status <> 'draft' then
    raise exception 'insufficient_privilege: an application is created as a draft';
  end if;
  return new;
end;
$$;
create trigger admission_applications_protect_trigger
  before insert or update on public.admission_applications
  for each row execute function public.admission_applications_protect();

-- ---------------------------------------------------------------------------
-- 4. admission_application_documents — uploads (storage: private bucket
-- admission-documents, created in the storage migration section below).

create table public.admission_application_documents (
  id              uuid primary key default gen_random_uuid(),
  application_id  uuid not null references public.admission_applications (id) on delete cascade,
  school_id       uuid not null references public.schools (id) on delete cascade,
  requirement_id  uuid references public.admission_document_requirements (id) on delete set null,
  label           text not null check (char_length(label) > 0),
  storage_path    text not null,
  mime_type       text,
  size_bytes      integer,
  verified        boolean not null default false,
  verified_by     uuid references public.profiles (id) on delete set null,
  verified_at     timestamptz,
  uploaded_at     timestamptz not null default now()
);

comment on table public.admission_application_documents is 'A file attached to an application. storage_path points into the private admission-documents bucket. Registered by the public intake function (public_register_admission_document) or by staff; verified by staff.';

create index admission_application_documents_application_id_idx on public.admission_application_documents (application_id);
create index admission_application_documents_school_id_idx on public.admission_application_documents (school_id);

-- ---------------------------------------------------------------------------
-- 5. admission_application_events — the per-application timeline / audit.

create table public.admission_application_events (
  id               uuid primary key default gen_random_uuid(),
  application_id   uuid not null references public.admission_applications (id) on delete cascade,
  school_id        uuid not null references public.schools (id) on delete cascade,
  event_type       text not null check (char_length(event_type) > 0),
  from_status      public.admission_application_status,
  to_status        public.admission_application_status,
  note             text,
  actor_profile_id uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now()
);

comment on table public.admission_application_events is 'Append-only timeline for one application (submitted, status changes, notes, conversion). Written only by the workflow RPCs. No UPDATE/DELETE policy.';

create index admission_application_events_application_id_idx on public.admission_application_events (application_id, created_at);

-- ---------------------------------------------------------------------------
-- 6. Authorization helpers.

create or replace function public.can_view_admissions(target_school_id uuid)
returns boolean language sql stable as $$
  select (target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'vice_principal', 'admissions_officer', 'receptionist'))
    or public.is_platform_admin()
$$;
comment on function public.can_view_admissions(uuid) is 'Mirrors the app-level admission.view permission (ROLE_PERMISSIONS). Keep in sync manually.';

create or replace function public.can_manage_admissions(target_school_id uuid)
returns boolean language sql stable as $$
  select (target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        ('school_owner', 'principal', 'admissions_officer'))
    or public.is_platform_admin()
$$;
comment on function public.can_manage_admissions(uuid) is 'Mirrors the app-level admission.manage permission (ROLE_PERMISSIONS). Keep in sync manually.';

grant execute on function public.can_view_admissions(uuid) to authenticated;
grant execute on function public.can_manage_admissions(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. RLS.

alter table public.admission_document_requirements enable row level security;
alter table public.admission_document_requirements force row level security;
alter table public.admission_applications enable row level security;
alter table public.admission_applications force row level security;
alter table public.admission_application_documents enable row level security;
alter table public.admission_application_documents force row level security;
alter table public.admission_application_events enable row level security;
alter table public.admission_application_events force row level security;

create policy admission_document_requirements_select on public.admission_document_requirements
  for select to authenticated using (public.can_view_admissions(school_id));
create policy admission_document_requirements_insert on public.admission_document_requirements
  for insert to authenticated with check (public.can_manage_admissions(school_id));
create policy admission_document_requirements_update on public.admission_document_requirements
  for update to authenticated using (public.can_manage_admissions(school_id)) with check (public.can_manage_admissions(school_id));

create policy admission_applications_select on public.admission_applications
  for select to authenticated using (public.can_view_admissions(school_id));
create policy admission_applications_insert on public.admission_applications
  for insert to authenticated with check (public.can_manage_admissions(school_id) and status = 'draft');
create policy admission_applications_update on public.admission_applications
  for update to authenticated using (public.can_manage_admissions(school_id)) with check (public.can_manage_admissions(school_id));
-- No DELETE. status/decision columns still RPC-guarded by the protect trigger.

create policy admission_application_documents_select on public.admission_application_documents
  for select to authenticated using (public.can_view_admissions(school_id));
create policy admission_application_documents_insert on public.admission_application_documents
  for insert to authenticated with check (public.can_manage_admissions(school_id));
create policy admission_application_documents_update on public.admission_application_documents
  for update to authenticated using (public.can_manage_admissions(school_id)) with check (public.can_manage_admissions(school_id));

create policy admission_application_events_select on public.admission_application_events
  for select to authenticated using (public.can_view_admissions(school_id));
-- events are written only by SECURITY DEFINER RPCs.

-- ---------------------------------------------------------------------------
-- 8. Transition rules.

create or replace function public.admission_can_transition(
  p_from public.admission_application_status, p_to public.admission_application_status
) returns boolean language sql immutable as $$
  select case p_from
    when 'draft'              then p_to = 'submitted'
    when 'submitted'          then p_to in ('under_review','incomplete','waitlisted','rejected','withdrawn')
    when 'under_review'       then p_to in ('incomplete','interview_required','assessment_required','waitlisted','accepted','rejected','withdrawn')
    when 'incomplete'         then p_to in ('submitted','under_review','withdrawn')
    when 'interview_required' then p_to in ('under_review','assessment_required','waitlisted','accepted','rejected','withdrawn')
    when 'assessment_required' then p_to in ('under_review','interview_required','waitlisted','accepted','rejected','withdrawn')
    when 'waitlisted'        then p_to in ('under_review','interview_required','assessment_required','accepted','rejected','withdrawn')
    when 'accepted'          then p_to in ('enrolled','rejected','withdrawn')
    when 'rejected'          then p_to = 'under_review'
    when 'withdrawn'         then p_to = 'under_review'
    else false
  end
$$;

-- Internal: write an event row (under the write guard).
create or replace function public.admission_log_event_internal(
  p_application_id uuid, p_school_id uuid, p_event_type text,
  p_from public.admission_application_status, p_to public.admission_application_status, p_note text
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.admission_application_events (application_id, school_id, event_type, from_status, to_status, note, actor_profile_id)
  values (p_application_id, p_school_id, p_event_type, p_from, p_to, p_note, auth.uid());
end;
$$;
revoke execute on function public.admission_log_event_internal(uuid, uuid, text, public.admission_application_status, public.admission_application_status, text) from public;

-- ---------------------------------------------------------------------------
-- 9. Staff workflow RPCs.

create or replace function public.create_admission_application(
  p_school_id uuid,
  p_applicant_email text,
  p_applicant_first_name text,
  p_applicant_last_name text,
  p_learner_first_name text,
  p_learner_last_name text,
  p_academic_year_id uuid default null,
  p_requested_grade_id uuid default null,
  p_applicant_phone text default null,
  p_applicant_relationship text default null,
  p_learner_date_of_birth date default null
) returns public.admission_applications
language plpgsql security definer set search_path = public as $$
declare v_result public.admission_applications;
begin
  if not public.can_manage_admissions(p_school_id) then
    raise exception 'insufficient_privilege: cannot manage admissions for this school';
  end if;

  insert into public.admission_applications (
    school_id, academic_year_id, requested_grade_id, applicant_email, applicant_first_name, applicant_last_name,
    applicant_phone, applicant_relationship, learner_first_name, learner_last_name, learner_date_of_birth
  ) values (
    p_school_id, p_academic_year_id, p_requested_grade_id, lower(trim(p_applicant_email)), p_applicant_first_name, p_applicant_last_name,
    p_applicant_phone, p_applicant_relationship, p_learner_first_name, p_learner_last_name, p_learner_date_of_birth
  ) returning * into v_result;

  perform public.admission_log_event_internal(v_result.id, p_school_id, 'created', null, 'draft', 'Created by staff');
  perform public.write_audit_log(p_school_id, auth.uid(), 'admission_application_created', 'admission_applications', v_result.id, null,
    jsonb_build_object('applicant_email', v_result.applicant_email));
  return v_result;
end;
$$;
revoke execute on function public.create_admission_application(uuid, text, text, text, text, text, uuid, uuid, text, text, date) from public;
grant execute on function public.create_admission_application(uuid, text, text, text, text, text, uuid, uuid, text, text, date) to authenticated;

create or replace function public.submit_admission_application(p_application_id uuid)
returns public.admission_applications
language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications; v_ref text; v_result public.admission_applications;
begin
  select * into v_app from public.admission_applications where id = p_application_id;
  if not found then raise exception 'not_found: no application %', p_application_id; end if;
  if not public.can_manage_admissions(v_app.school_id) then
    raise exception 'insufficient_privilege: cannot manage admissions for this school';
  end if;
  if v_app.status <> 'draft' then raise exception 'invalid_state: only a draft application can be submitted'; end if;
  if coalesce(trim(v_app.learner_first_name), '') = '' or coalesce(trim(v_app.learner_last_name), '') = '' then
    raise exception 'invalid_argument: the learner name is required before submitting';
  end if;

  v_ref := public.next_admission_reference(v_app.school_id);
  perform set_config('app.allow_admission_write', 'true', true);
  update public.admission_applications
    set status = 'submitted', reference_number = v_ref, submitted_at = now()
    where id = p_application_id returning * into v_result;
  perform set_config('app.allow_admission_write', 'false', true);

  perform public.admission_log_event_internal(p_application_id, v_app.school_id, 'submitted', 'draft', 'submitted', null);
  perform public.write_audit_log(v_app.school_id, auth.uid(), 'admission_application_submitted', 'admission_applications', p_application_id, null,
    jsonb_build_object('reference_number', v_ref));
  return v_result;
end;
$$;
revoke execute on function public.submit_admission_application(uuid) from public;
grant execute on function public.submit_admission_application(uuid) to authenticated;

create or replace function public.transition_admission_application(
  p_application_id uuid, p_to public.admission_application_status, p_note text default null
) returns public.admission_applications
language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications; v_result public.admission_applications;
begin
  select * into v_app from public.admission_applications where id = p_application_id for update;
  if not found then raise exception 'not_found: no application %', p_application_id; end if;
  if not public.can_manage_admissions(v_app.school_id) then
    raise exception 'insufficient_privilege: cannot manage admissions for this school';
  end if;
  if p_to = 'enrolled' then
    raise exception 'invalid_state: use convert_admission_application() to enrol an accepted applicant';
  end if;
  if not public.admission_can_transition(v_app.status, p_to) then
    raise exception 'invalid_state: cannot move an application from % to %', v_app.status, p_to;
  end if;

  perform set_config('app.allow_admission_write', 'true', true);
  update public.admission_applications set
    status = p_to,
    decision_at = case when p_to in ('accepted','rejected','waitlisted') then now() else decision_at end,
    decision_by = case when p_to in ('accepted','rejected','waitlisted') then auth.uid() else decision_by end,
    decision_reason = case when p_to in ('accepted','rejected','waitlisted') then p_note else decision_reason end
    where id = p_application_id returning * into v_result;
  perform set_config('app.allow_admission_write', 'false', true);

  perform public.admission_log_event_internal(p_application_id, v_app.school_id, 'status_changed', v_app.status, p_to, p_note);
  perform public.write_audit_log(v_app.school_id, auth.uid(), 'admission_application_' || p_to, 'admission_applications', p_application_id,
    jsonb_build_object('status', v_app.status), jsonb_build_object('status', p_to, 'note', p_note));
  return v_result;
end;
$$;
revoke execute on function public.transition_admission_application(uuid, public.admission_application_status, text) from public;
grant execute on function public.transition_admission_application(uuid, public.admission_application_status, text) to authenticated;

create or replace function public.add_admission_application_note(p_application_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_school uuid;
begin
  select school_id into v_school from public.admission_applications where id = p_application_id;
  if v_school is null then raise exception 'not_found: no application %', p_application_id; end if;
  if not public.can_manage_admissions(v_school) then
    raise exception 'insufficient_privilege: cannot manage admissions for this school';
  end if;
  if p_note is null or char_length(trim(p_note)) = 0 then raise exception 'invalid_argument: note is empty'; end if;
  perform public.admission_log_event_internal(p_application_id, v_school, 'note', null, null, p_note);
end;
$$;
revoke execute on function public.add_admission_application_note(uuid, text) from public;
grant execute on function public.add_admission_application_note(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Conversion — accepted application -> learner + guardian + enrolment.

create or replace function public.convert_admission_application(
  p_application_id uuid,
  p_class_id uuid default null,
  p_provision_guardian_account boolean default true
) returns public.admission_applications
language plpgsql security definer set search_path = public as $$
declare
  v_app public.admission_applications;
  v_year uuid;
  v_grade uuid;
  v_class_school uuid;
  v_learner_id uuid;
  v_learner_number text;
  v_admission_number text;
  v_seq bigint;
  v_guardian_profile uuid;
  v_result public.admission_applications;
begin
  select * into v_app from public.admission_applications where id = p_application_id for update;
  if not found then raise exception 'not_found: no application %', p_application_id; end if;
  if not public.can_manage_admissions(v_app.school_id) then
    raise exception 'insufficient_privilege: cannot manage admissions for this school';
  end if;
  if v_app.status <> 'accepted' then
    raise exception 'invalid_state: only an accepted application can be converted (current: %)', v_app.status;
  end if;
  if v_app.converted_learner_id is not null then
    raise exception 'already_converted: this application already produced learner %', v_app.converted_learner_id;
  end if;

  v_year := v_app.academic_year_id;
  if v_year is null then
    select id into v_year from public.academic_years where school_id = v_app.school_id and is_active order by start_date desc limit 1;
  end if;
  if v_year is null then raise exception 'invalid_state: no academic year on the application and no active year for the school'; end if;

  v_grade := v_app.requested_grade_id;
  if v_grade is null then
    raise exception 'invalid_argument: set the requested grade on the application before converting';
  end if;

  if p_class_id is not null then
    select school_id into v_class_school from public.classes where id = p_class_id;
    if v_class_school is distinct from v_app.school_id then
      raise exception 'insufficient_privilege: class_id must belong to the same school';
    end if;
  end if;

  -- Generate learner/admission numbers off the same per-school counter.
  insert into public.admission_counters (school_id, next_value) values (v_app.school_id, 1)
  on conflict (school_id) do nothing;
  update public.admission_counters set next_value = next_value + 1 where school_id = v_app.school_id returning next_value - 1 into v_seq;
  v_learner_number := 'LRN-' || to_char(now() at time zone 'Africa/Johannesburg', 'YY') || '-' || lpad(v_seq::text, 5, '0');
  v_admission_number := 'ADM-' || to_char(now() at time zone 'Africa/Johannesburg', 'YY') || '-' || lpad(v_seq::text, 5, '0');

  insert into public.learners (
    school_id, learner_number, admission_number, first_name, last_name, date_of_birth,
    gender, id_number, nationality, home_language, status, admission_date
  ) values (
    v_app.school_id, v_learner_number, v_admission_number,
    coalesce(v_app.learner_first_name, 'Unknown'), coalesce(v_app.learner_last_name, 'Applicant'),
    coalesce(v_app.learner_date_of_birth, '2000-01-01'),
    v_app.learner_gender, v_app.learner_id_number, v_app.learner_nationality, v_app.learner_home_language,
    'accepted', current_date
  ) returning id into v_learner_id;

  -- Guardian: reuse an existing profile at this school with the same email,
  -- otherwise create one. admin_create_guardian raises 'email_taken' for a
  -- global collision, so check first.
  select id into v_guardian_profile from public.profiles
    where lower(email) = lower(v_app.applicant_email) and tenant_id = v_app.school_id limit 1;

  if v_guardian_profile is null and not exists (select 1 from auth.users where lower(email) = lower(v_app.applicant_email)) then
    select user_id into v_guardian_profile from public.admin_create_guardian(
      lower(v_app.applicant_email),
      coalesce(v_app.applicant_first_name, 'Guardian'),
      coalesce(v_app.applicant_last_name, v_app.learner_last_name, 'Applicant'),
      v_app.applicant_phone, v_app.school_id, null, null
    );
  end if;

  if v_guardian_profile is not null then
    insert into public.learner_guardians (school_id, learner_id, guardian_profile_id, relationship_type, is_primary)
    values (v_app.school_id, v_learner_id,
            v_guardian_profile,
            case lower(coalesce(v_app.applicant_relationship, ''))
              when 'mother' then 'mother' when 'father' then 'father'
              when 'legal_guardian' then 'legal_guardian' when 'grandparent' then 'grandparent'
              else 'other' end::public.guardian_relationship_type,
            true)
    on conflict do nothing;

    if p_provision_guardian_account then
      perform public.send_guardian_invitation(v_guardian_profile, 168);
    end if;
  end if;

  insert into public.learner_enrollments (school_id, learner_id, academic_year_id, grade_id, class_id, enrollment_date, enrollment_status)
  values (v_app.school_id, v_learner_id, v_year, v_grade, p_class_id, current_date, 'enrolled');

  perform set_config('app.allow_admission_write', 'true', true);
  update public.admission_applications set status = 'enrolled', converted_learner_id = v_learner_id
    where id = p_application_id returning * into v_result;
  perform set_config('app.allow_admission_write', 'false', true);

  perform public.admission_log_event_internal(p_application_id, v_app.school_id, 'converted', 'accepted', 'enrolled',
    'Learner ' || v_learner_number || ' created');
  perform public.write_audit_log(v_app.school_id, auth.uid(), 'admission_application_converted', 'admission_applications', p_application_id, null,
    jsonb_build_object('learner_id', v_learner_id, 'guardian_profile_id', v_guardian_profile));
  return v_result;
end;
$$;
revoke execute on function public.convert_admission_application(uuid, uuid, boolean) from public;
grant execute on function public.convert_admission_application(uuid, uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Public intake RPCs — service_role only (the admissions-public Edge
-- Function). No anon/authenticated grant.

create or replace function public.public_start_admission_application(
  p_school_id uuid, p_applicant_email text, p_payload jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_token uuid;
begin
  if not exists (select 1 from public.schools where id = p_school_id and status = 'active') then
    raise exception 'not_found: no active school %', p_school_id;
  end if;
  insert into public.admission_applications (
    school_id, applicant_email, is_public_submission,
    applicant_first_name, applicant_last_name, applicant_phone, applicant_relationship,
    learner_first_name, learner_last_name, learner_date_of_birth, learner_gender,
    learner_id_number, learner_nationality, learner_home_language, prior_school, additional_notes,
    academic_year_id, requested_grade_id
  ) values (
    p_school_id, lower(trim(p_applicant_email)), true,
    p_payload->>'applicant_first_name', p_payload->>'applicant_last_name', p_payload->>'applicant_phone', p_payload->>'applicant_relationship',
    p_payload->>'learner_first_name', p_payload->>'learner_last_name', (p_payload->>'learner_date_of_birth')::date, p_payload->>'learner_gender',
    p_payload->>'learner_id_number', p_payload->>'learner_nationality', p_payload->>'learner_home_language', p_payload->>'prior_school', p_payload->>'additional_notes',
    nullif(p_payload->>'academic_year_id','')::uuid, nullif(p_payload->>'requested_grade_id','')::uuid
  ) returning id, resume_token into v_id, v_token;

  perform public.admission_log_event_internal(v_id, p_school_id, 'created', null, 'draft', 'Public application started');
  return jsonb_build_object('application_id', v_id, 'resume_token', v_token);
end;
$$;

create or replace function public.public_save_admission_application(p_resume_token uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications;
begin
  select * into v_app from public.admission_applications where resume_token = p_resume_token;
  if not found then raise exception 'not_found: invalid resume token'; end if;
  if v_app.status not in ('draft', 'incomplete') then
    raise exception 'invalid_state: this application can no longer be edited online';
  end if;

  perform set_config('app.allow_admission_write', 'true', true);
  update public.admission_applications set
    applicant_first_name = coalesce(p_payload->>'applicant_first_name', applicant_first_name),
    applicant_last_name  = coalesce(p_payload->>'applicant_last_name', applicant_last_name),
    applicant_phone      = coalesce(p_payload->>'applicant_phone', applicant_phone),
    applicant_relationship = coalesce(p_payload->>'applicant_relationship', applicant_relationship),
    learner_first_name   = coalesce(p_payload->>'learner_first_name', learner_first_name),
    learner_last_name    = coalesce(p_payload->>'learner_last_name', learner_last_name),
    learner_date_of_birth = coalesce((p_payload->>'learner_date_of_birth')::date, learner_date_of_birth),
    learner_gender       = coalesce(p_payload->>'learner_gender', learner_gender),
    learner_id_number    = coalesce(p_payload->>'learner_id_number', learner_id_number),
    learner_nationality  = coalesce(p_payload->>'learner_nationality', learner_nationality),
    learner_home_language = coalesce(p_payload->>'learner_home_language', learner_home_language),
    prior_school         = coalesce(p_payload->>'prior_school', prior_school),
    additional_notes     = coalesce(p_payload->>'additional_notes', additional_notes),
    academic_year_id     = coalesce(nullif(p_payload->>'academic_year_id','')::uuid, academic_year_id),
    requested_grade_id   = coalesce(nullif(p_payload->>'requested_grade_id','')::uuid, requested_grade_id),
    -- re-opening an 'incomplete' application by editing puts it back to draft
    status = case when status = 'incomplete' then 'draft'::public.admission_application_status else status end
    where resume_token = p_resume_token;
  perform set_config('app.allow_admission_write', 'false', true);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.public_submit_admission_application(p_resume_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications; v_ref text;
begin
  select * into v_app from public.admission_applications where resume_token = p_resume_token;
  if not found then raise exception 'not_found: invalid resume token'; end if;
  if v_app.status <> 'draft' then raise exception 'invalid_state: this application is not a draft'; end if;
  if coalesce(trim(v_app.learner_first_name),'') = '' or coalesce(trim(v_app.learner_last_name),'') = ''
     or coalesce(trim(v_app.applicant_first_name),'') = '' then
    raise exception 'invalid_argument: applicant name and learner name are required';
  end if;

  v_ref := public.next_admission_reference(v_app.school_id);
  perform set_config('app.allow_admission_write', 'true', true);
  update public.admission_applications set status = 'submitted', reference_number = v_ref, submitted_at = now()
    where resume_token = p_resume_token;
  perform set_config('app.allow_admission_write', 'false', true);

  perform public.admission_log_event_internal(v_app.id, v_app.school_id, 'submitted', 'draft', 'submitted', 'Public submission');
  return jsonb_build_object('reference_number', v_ref);
end;
$$;

create or replace function public.public_get_admission_application(p_resume_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications;
begin
  select * into v_app from public.admission_applications where resume_token = p_resume_token;
  if not found then return jsonb_build_object('found', false); end if;
  if v_app.status not in ('draft', 'incomplete') then
    return jsonb_build_object('found', true, 'editable', false, 'status', v_app.status, 'reference_number', v_app.reference_number);
  end if;
  return jsonb_build_object('found', true, 'editable', true, 'status', v_app.status, 'application', to_jsonb(v_app) - 'resume_token');
end;
$$;

create or replace function public.public_resume_admission_application(p_email text, p_reference text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications;
begin
  select * into v_app from public.admission_applications
    where lower(applicant_email) = lower(trim(p_email)) and reference_number = trim(p_reference);
  if not found then return jsonb_build_object('found', false); end if;
  return jsonb_build_object(
    'found', true,
    'resume_token', case when v_app.status in ('draft','incomplete') then v_app.resume_token else null end,
    'status', v_app.status,
    'reference_number', v_app.reference_number,
    'application', to_jsonb(v_app) - 'resume_token'
  );
end;
$$;

create or replace function public.public_register_admission_document(
  p_resume_token uuid, p_label text, p_storage_path text, p_mime_type text, p_size_bytes integer, p_requirement_id uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_app public.admission_applications; v_doc_id uuid;
begin
  select * into v_app from public.admission_applications where resume_token = p_resume_token;
  if not found then raise exception 'not_found: invalid resume token'; end if;
  if v_app.status not in ('draft','incomplete','submitted','under_review') then
    raise exception 'invalid_state: documents can no longer be added to this application';
  end if;
  insert into public.admission_application_documents (application_id, school_id, requirement_id, label, storage_path, mime_type, size_bytes)
  values (v_app.id, v_app.school_id, p_requirement_id, p_label, p_storage_path, p_mime_type, p_size_bytes)
  returning id into v_doc_id;
  perform public.admission_log_event_internal(v_app.id, v_app.school_id, 'document_uploaded', null, null, p_label);
  return jsonb_build_object('document_id', v_doc_id);
end;
$$;

revoke execute on function public.public_start_admission_application(uuid, text, jsonb) from public;
revoke execute on function public.public_save_admission_application(uuid, jsonb) from public;
revoke execute on function public.public_submit_admission_application(uuid) from public;
revoke execute on function public.public_get_admission_application(uuid) from public;
revoke execute on function public.public_resume_admission_application(text, text) from public;
revoke execute on function public.public_register_admission_document(uuid, text, text, text, integer, uuid) from public;
grant execute on function public.public_start_admission_application(uuid, text, jsonb) to service_role;
grant execute on function public.public_save_admission_application(uuid, jsonb) to service_role;
grant execute on function public.public_submit_admission_application(uuid) to service_role;
grant execute on function public.public_get_admission_application(uuid) to service_role;
grant execute on function public.public_resume_admission_application(text, text) to service_role;
grant execute on function public.public_register_admission_document(uuid, text, text, text, integer, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 12. Private storage bucket for application documents + storage RLS.

insert into storage.buckets (id, name, public)
values ('admission-documents', 'admission-documents', false)
on conflict (id) do nothing;

-- Path convention: <school_id>/<application_id>/<filename>. Staff who can
-- manage admissions for the school may read/write; nobody else. The public
-- intake function uploads with the service_role key (bypasses this).
create policy admission_documents_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'admission-documents'
    and public.can_view_admissions((storage.foldername(name))[1]::uuid)
  );
create policy admission_documents_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'admission-documents'
    and public.can_manage_admissions((storage.foldername(name))[1]::uuid)
  );
create policy admission_documents_update on storage.objects
  for update to authenticated
  using (bucket_id = 'admission-documents' and public.can_manage_admissions((storage.foldername(name))[1]::uuid));
