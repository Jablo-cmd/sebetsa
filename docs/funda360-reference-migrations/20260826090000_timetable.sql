-- Timetable Management
--
-- Phase 1 audit findings (confirmed by inspection, not assumed):
--   - Teachers are `profiles` rows (role in teacher/class_teacher/
--     subject_teacher), referenced directly — exactly how
--     class_teacher_assignments.teacher_profile_id already does it. No
--     separate "teacher" entity exists or is needed here either.
--   - class_teacher_assignments already answers "who is responsible for
--     this class/subject" but carries no day/time — it is a
--     responsibility record, not a schedule. This migration does not
--     require a class_teacher_assignments row to exist first (same
--     precedent as assessments, which independently references class_id/
--     subject_id without going through that table) — requiring one would
--     force every school to fully staff class_teacher_assignments before
--     they could build a timetable, which is not a real constraint set up
--     anywhere else in this schema and is not requested by the brief.
--   - classes/subjects/grades/terms/academic_years/class_teacher_assignments
--     all share exactly two permission functions: can_view_academic()
--     (school_owner, principal, teacher, class_teacher, subject_teacher)
--     and can_manage_academic() (school_owner, principal). Reused directly
--     — no new permission function was needed at the database layer, only
--     new app-level Permission entries (timetable.view/timetable.manage)
--     for route-gating granularity, matching how attendance.view/
--     attendance.manage exist as their own Permission despite
--     attendance_records_select also just calling can_view_academic().
--   - Rooms/classrooms do not exist anywhere in this schema. Per the
--     brief, a plain nullable text `room` column is used instead of a
--     rooms subsystem.
--   - Days of the week are not represented anywhere yet — a new enum is
--     introduced here, scoped to this table only.
--   - No existing timetable/calendar code exists anywhere in this
--     codebase (confirmed by search) — this is a genuinely new domain.
--
-- TERM HANDLING: term_id is nullable, not required. Most schools run one
-- timetable for the whole academic year; a null term_id means "applies for
-- the whole year". A school that wants a term-specific schedule change may
-- set term_id on just those entries. This avoids forcing every school into
-- term-level timetabling when the brief does not establish that as a firm
-- requirement ("if the existing architecture does not require term-level
-- timetables, document the decision rather than inventing unnecessary
-- complexity").
--
-- CONFLICT DETECTION SCOPE: conflict checks below compare active entries
-- within the same (school_id, academic_year_id, day_of_week) regardless of
-- term_id. A teacher/class/room genuinely cannot be in two places at once
-- on the same weekday within the same year, independent of which term_id
-- either entry happens to carry — scoping conflict checks by term as well
-- would let two term-scoped entries silently overlap in real wall-clock
-- time whenever their term_id values differ, which is the wrong default
-- for a scheduling system. Erring toward stricter conflict rejection
-- rather than a narrower, term-precise check is the deliberate,
-- documented choice here.

create type public.day_of_week as enum ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday');

comment on type public.day_of_week is 'Introduced for timetable_entries — no prior representation of weekdays existed anywhere in this schema.';

create table public.timetable_entries (
  id                  uuid primary key default gen_random_uuid(),
  school_id           uuid not null references public.schools (id) on delete cascade,
  academic_year_id    uuid not null references public.academic_years (id),
  term_id             uuid references public.terms (id),
  class_id            uuid not null references public.classes (id),
  subject_id          uuid not null references public.subjects (id),
  teacher_profile_id  uuid not null references public.profiles (id) on delete cascade,
  day_of_week         public.day_of_week not null,
  start_time          time not null,
  end_time            time not null,
  room                text,
  active              boolean not null default true,
  created_by          uuid references public.profiles (id) on delete set null,
  updated_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint timetable_entries_time_valid check (end_time > start_time)
);

comment on table public.timetable_entries is 'One scheduled lesson: a class + subject + teacher at a day/time, optionally a room, for an academic year (optionally scoped to one term). Never hard-deleted — active=false is the archive state, same pattern as every other entity table in this schema.';
comment on column public.timetable_entries.term_id is 'NULL = applies for the whole academic year. Set only when a school needs a term-specific schedule change — see migration header.';
comment on column public.timetable_entries.room is 'Plain free-text location — this schema has no rooms/classrooms subsystem, and building one is out of scope for this feature. Same treatment as learners.gender/transport_mode (open text, no invented taxonomy).';

create index timetable_entries_school_id_idx on public.timetable_entries (school_id);
create index timetable_entries_academic_year_id_idx on public.timetable_entries (academic_year_id);
create index timetable_entries_term_id_idx on public.timetable_entries (term_id);
create index timetable_entries_class_id_idx on public.timetable_entries (class_id);
create index timetable_entries_subject_id_idx on public.timetable_entries (subject_id);
create index timetable_entries_teacher_profile_id_idx on public.timetable_entries (teacher_profile_id);
-- Composite indexes matching the three conflict-check queries below exactly.
create index timetable_entries_teacher_conflict_idx on public.timetable_entries (teacher_profile_id, academic_year_id, day_of_week) where active;
create index timetable_entries_class_conflict_idx on public.timetable_entries (class_id, academic_year_id, day_of_week) where active;
create index timetable_entries_room_conflict_idx on public.timetable_entries (school_id, room, academic_year_id, day_of_week) where active and room is not null;

create trigger timetable_entries_set_updated_at
  before update on public.timetable_entries
  for each row
  execute function public.set_updated_at();

create trigger timetable_entries_set_created_updated_by
  before insert or update on public.timetable_entries
  for each row
  execute function public.set_created_updated_by();

-- Plain SECURITY INVOKER, not reflexive SECURITY DEFINER: the only actors
-- who can ever reach this trigger (can_manage_academic() = school_owner/
-- principal) already hold can_view_academic() too, so their own RLS
-- already lets them read academic_years/terms/classes/subjects/profiles —
-- exactly class_teacher_assignments_validate_tenant()'s own reasoning,
-- reused here, not copied reflexively.
create or replace function public.timetable_entries_validate_tenant()
returns trigger
language plpgsql
as $$
declare
  v_year_school_id uuid;
  v_term_school_id uuid;
  v_term_academic_year_id uuid;
  v_class_school_id uuid;
  v_subject_school_id uuid;
  v_teacher_tenant_id uuid;
begin
  select school_id into v_year_school_id from public.academic_years where id = new.academic_year_id;
  if v_year_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: academic_year_id must belong to the same school';
  end if;

  if new.term_id is not null then
    select school_id, academic_year_id into v_term_school_id, v_term_academic_year_id
      from public.terms where id = new.term_id;
    if v_term_school_id is distinct from new.school_id then
      raise exception 'insufficient_privilege: term_id must belong to the same school';
    end if;
    if v_term_academic_year_id is distinct from new.academic_year_id then
      raise exception 'insufficient_privilege: term_id must belong to the same academic year';
    end if;
  end if;

  select school_id into v_class_school_id from public.classes where id = new.class_id;
  if v_class_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: class_id must belong to the same school';
  end if;

  select school_id into v_subject_school_id from public.subjects where id = new.subject_id;
  if v_subject_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: subject_id must belong to the same school';
  end if;

  select tenant_id into v_teacher_tenant_id from public.profiles where id = new.teacher_profile_id;
  if v_teacher_tenant_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: teacher_profile_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger timetable_entries_validate_tenant_trigger
  before insert or update on public.timetable_entries
  for each row
  execute function public.timetable_entries_validate_tenant();

-- Conflict detection — enforced at the database layer, not only in the
-- frontend, per the brief. An archived (active=false) entry can never
-- conflict with anything, and is exempted immediately so archiving is
-- always possible regardless of what else is scheduled. Overlap test is
-- the standard half-open-interval check: two ranges [a,b) and [c,d)
-- overlap iff a < d and c < b.
create or replace function public.timetable_entries_check_conflicts()
returns trigger
language plpgsql
as $$
declare
  v_conflict_id uuid;
begin
  if not new.active then
    return new;
  end if;

  select id into v_conflict_id from public.timetable_entries
    where id is distinct from new.id
      and academic_year_id = new.academic_year_id
      and day_of_week = new.day_of_week
      and teacher_profile_id = new.teacher_profile_id
      and active
      and start_time < new.end_time and new.start_time < end_time
    limit 1;
  if v_conflict_id is not null then
    raise exception 'conflict: teacher already has an overlapping lesson scheduled on %', new.day_of_week;
  end if;

  select id into v_conflict_id from public.timetable_entries
    where id is distinct from new.id
      and academic_year_id = new.academic_year_id
      and day_of_week = new.day_of_week
      and class_id = new.class_id
      and active
      and start_time < new.end_time and new.start_time < end_time
    limit 1;
  if v_conflict_id is not null then
    raise exception 'conflict: this class already has an overlapping lesson scheduled on %', new.day_of_week;
  end if;

  if new.room is not null then
    select id into v_conflict_id from public.timetable_entries
      where id is distinct from new.id
        and school_id = new.school_id
        and academic_year_id = new.academic_year_id
        and day_of_week = new.day_of_week
        and room = new.room
        and active
        and start_time < new.end_time and new.start_time < end_time
      limit 1;
    if v_conflict_id is not null then
      raise exception 'conflict: room "%" is already booked for an overlapping time on %', new.room, new.day_of_week;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.timetable_entries_check_conflicts() is
  'Enforces teacher/class/room non-overlap at the database layer — the real security/correctness boundary, not merely a UI convenience. Fires on every INSERT and UPDATE, so a conflict introduced by editing an existing entry (e.g. changing its time) is rejected exactly like a conflict introduced by a new one.';

create trigger timetable_entries_check_conflicts_trigger
  before insert or update on public.timetable_entries
  for each row
  execute function public.timetable_entries_check_conflicts();

alter table public.timetable_entries enable row level security;
alter table public.timetable_entries force row level security;

-- Reuses can_view_academic()/can_manage_academic() directly — the exact
-- same actor set already governs classes/grades/subjects/terms/
-- academic_years/class_teacher_assignments/attendance_records/assessments.
-- No new permission function was needed.
create policy timetable_entries_select on public.timetable_entries
  for select to authenticated using (public.can_view_academic(school_id));
create policy timetable_entries_insert on public.timetable_entries
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy timetable_entries_update on public.timetable_entries
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete
-- is impossible for any authenticated caller, same as every other table
-- in this schema. active=false is the only archive path.
