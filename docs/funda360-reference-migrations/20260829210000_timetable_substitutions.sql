-- FND-TT-004: Substitute-teacher handling.
--
-- A substitution is a ONE-OFF, dated override of a single recurring
-- timetable_entries row ("Ms. X is out sick on 12 Sept, Mr. Y is covering
-- her Grade 8A Maths lesson that day") — not a change to the recurring
-- weekly schedule itself. Modeled as its own table referencing the
-- timetable_entries row it covers, rather than a mutable field on
-- timetable_entries, because the regular teacher/day/time must stay
-- exactly as scheduled for every OTHER date; only this one calendar date
-- is different. Same reasoning as learner_transfers not overwriting
-- learners.status: the original schedule is the ongoing truth, this is a
-- dated exception layered on top of it.
--
-- RBAC: reuses can_view_academic()/can_manage_academic() verbatim — the
-- exact same actor set that already owns the recurring timetable_entries
-- row this table extends.
--
-- SECURITY DEFINER on the tenant/consistency trigger — same reasoning as
-- every other validate_tenant() function in this schema: it reads
-- timetable_entries and profiles, gated by permissions teacher/class_
-- teacher/subject_teacher (who can view but not manage) do not hold.

create table public.timetable_substitutions (
  id                            uuid primary key default gen_random_uuid(),
  school_id                     uuid not null references public.schools (id) on delete cascade,
  timetable_entry_id            uuid not null references public.timetable_entries (id) on delete cascade,
  substitute_date               date not null,
  substitute_teacher_profile_id uuid not null references public.profiles (id) on delete cascade,
  reason                        text,
  notes                         text,
  created_by                    uuid references public.profiles (id) on delete set null,
  updated_by                    uuid references public.profiles (id) on delete set null,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  constraint timetable_substitutions_unique_entry_date unique (timetable_entry_id, substitute_date)
);

comment on table public.timetable_substitutions is 'A one-off, dated substitute-teacher assignment covering a single occurrence of a recurring timetable_entries lesson. Does not modify the recurring entry itself — every other date keeps the regular teacher. Never hard-deleted in the UI sense (no archive flag needed — a substitution scoped to a single past date has no ongoing state to archive), but IS hard-deletable by design (see DELETE policy below) since cancelling a substitution before the date arrives should remove it outright, not leave a dangling record with no meaning.';
comment on column public.timetable_substitutions.substitute_date is 'The single calendar date this substitution applies to. Validated by timetable_substitutions_validate_tenant() to actually fall on the entry''s own day_of_week — a Monday lesson cannot be "substituted" for a Tuesday date.';

create index timetable_substitutions_school_id_idx on public.timetable_substitutions (school_id);
create index timetable_substitutions_entry_id_idx on public.timetable_substitutions (timetable_entry_id);
create index timetable_substitutions_date_idx on public.timetable_substitutions (substitute_date);
create index timetable_substitutions_teacher_idx on public.timetable_substitutions (substitute_teacher_profile_id);

create trigger timetable_substitutions_set_updated_at
  before update on public.timetable_substitutions
  for each row
  execute function public.set_updated_at();

create trigger timetable_substitutions_set_created_updated_by
  before insert or update on public.timetable_substitutions
  for each row
  execute function public.set_created_updated_by();

create or replace function public.timetable_substitutions_validate_tenant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry record;
  v_teacher_tenant uuid;
  v_expected_day public.day_of_week;
begin
  select school_id, day_of_week into v_entry from public.timetable_entries where id = new.timetable_entry_id;
  if v_entry.school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: timetable_entry_id must belong to the same school';
  end if;

  v_expected_day := trim(lower(to_char(new.substitute_date, 'FMDay')))::public.day_of_week;
  if v_expected_day is distinct from v_entry.day_of_week then
    raise exception 'insufficient_privilege: substitute_date (%) falls on a % but the lesson is scheduled for %', new.substitute_date, v_expected_day, v_entry.day_of_week;
  end if;

  select tenant_id into v_teacher_tenant from public.profiles where id = new.substitute_teacher_profile_id;
  if v_teacher_tenant is distinct from new.school_id then
    raise exception 'insufficient_privilege: substitute_teacher_profile_id must belong to the same school';
  end if;

  return new;
end;
$$;

create trigger timetable_substitutions_validate_tenant_trigger
  before insert or update on public.timetable_substitutions
  for each row
  execute function public.timetable_substitutions_validate_tenant();

-- ---------------------------------------------------------------------------
-- RLS — identical actor set to timetable_entries.

alter table public.timetable_substitutions enable row level security;
alter table public.timetable_substitutions force row level security;

create policy timetable_substitutions_select on public.timetable_substitutions
  for select to authenticated using (public.can_view_academic(school_id));
create policy timetable_substitutions_insert on public.timetable_substitutions
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy timetable_substitutions_update on public.timetable_substitutions
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

-- Unlike most tables in this schema, a genuine DELETE policy exists here:
-- a substitution is a dated exception with no meaning once cancelled
-- (there is no "restore" concept the way active=false has elsewhere) — the
-- correct undo for "assigned the wrong cover teacher" is removing the row
-- outright, not soft-archiving a fact nobody needs to see again.
create policy timetable_substitutions_delete on public.timetable_substitutions
  for delete to authenticated using (public.can_manage_academic(school_id));
