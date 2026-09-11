-- Attendance Domain
--
-- Daily class attendance: one row per (learner, class, date), matching the
-- homeroom-style daily register schools actually take (there is no
-- period/timetable table in this schema to attach per-subject attendance
-- to, so this deliberately does not invent one — see the pasted example
-- this feature was built from: one status per learner per class per day,
-- no period/subject dimension).
--
-- Recording is class-scoped, not a single school-wide manage permission:
-- school_owner/principal can record for any class (reusing
-- can_manage_academic()); a teacher can record only for a class they hold
-- an active class_teacher_assignments row for. Any subject_id qualifies —
-- this schema has no concept of a homeroom teacher distinct from a subject
-- teacher, so whichever teacher is assigned to the class may take its daily
-- register rather than inventing that distinction. Viewing reuses
-- can_view_academic() wholesale, the same "a teacher already sees the whole
-- academic structure" reasoning class_teacher_assignments documented.
--
-- A mismarked entry is corrected via UPDATE, not a soft-delete/re-insert —
-- there is no "undo taking the register" concept, so (like every other
-- table in this schema) there is no DELETE policy at all.

create type public.attendance_status as enum ('present', 'absent', 'late');

create table public.attendance_records (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools (id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years (id),
  class_id          uuid not null references public.classes (id),
  learner_id        uuid not null references public.learners (id) on delete cascade,
  attendance_date   date not null,
  status            public.attendance_status not null,
  notes             text,
  created_by        uuid references public.profiles (id) on delete set null,
  updated_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.attendance_records is 'Daily attendance — one row per (learner, class, attendance_date). Corrections are UPDATEs; there is no DELETE policy, same as every other table in this schema.';

create unique index attendance_records_unique_idx on public.attendance_records (learner_id, class_id, attendance_date);
create index attendance_records_school_id_idx on public.attendance_records (school_id);
create index attendance_records_class_id_idx on public.attendance_records (class_id);
create index attendance_records_academic_year_id_idx on public.attendance_records (academic_year_id);
create index attendance_records_learner_id_idx on public.attendance_records (learner_id);
create index attendance_records_date_idx on public.attendance_records (attendance_date);

create trigger attendance_records_set_updated_at
  before update on public.attendance_records
  for each row
  execute function public.set_updated_at();

create trigger attendance_records_set_created_updated_by
  before insert or update on public.attendance_records
  for each row
  execute function public.set_created_updated_by();

-- Closes the FK-doesn't-respect-RLS gap for every reference this row makes,
-- same pattern as class_teacher_assignments_validate_tenant().
create or replace function public.attendance_records_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_year_school_id uuid;
  v_class_school_id uuid;
  v_learner_school_id uuid;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  select school_id into v_class_school_id from public.classes where id = new.class_id;
  if v_class_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: class_id must belong to the same school';
  end if;

  select school_id into v_learner_school_id from public.learners where id = new.learner_id;
  if v_learner_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: learner_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger attendance_records_validate_tenant_trigger
  before insert or update on public.attendance_records
  for each row
  execute function public.attendance_records_validate_tenant();

-- Mirrors the app-level attendance.manage permission, scoped per class:
-- broad for school_owner/principal (can_manage_academic), narrow — their
-- own assigned classes only — for teacher-variant roles.
create or replace function public.can_record_attendance(target_school_id uuid, target_class_id uuid)
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

comment on function public.can_record_attendance(uuid, uuid) is
  'Mirrors the app-level attendance.manage permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts), scoped per class via class_teacher_assignments for teacher-variant roles. Keep in sync manually.';

grant execute on function public.can_record_attendance(uuid, uuid) to authenticated;

alter table public.attendance_records enable row level security;
alter table public.attendance_records force row level security;

create policy attendance_records_select on public.attendance_records
  for select to authenticated using (public.can_view_academic(school_id));
create policy attendance_records_insert on public.attendance_records
  for insert to authenticated with check (public.can_record_attendance(school_id, class_id));
create policy attendance_records_update on public.attendance_records
  for update to authenticated using (public.can_record_attendance(school_id, class_id)) with check (public.can_record_attendance(school_id, class_id));
