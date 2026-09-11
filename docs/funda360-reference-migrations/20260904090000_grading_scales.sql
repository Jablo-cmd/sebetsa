-- Report Cards domain (1/2) — Grading scales
--
-- A grading scale is a reusable, per-school lookup that maps a percentage
-- to an achievement code + label (e.g. SA CAPS 7-point: 80-100 -> "7 /
-- Outstanding achievement"). No such concept existed anywhere in the
-- schema — assessments/assessment_results store only raw integer marks
-- (see 20260817140000_assessments.sql: "No existing assessment/gradebook
-- taxonomy was found"). This migration adds it as its own small domain so
-- report-card templates (2/2) reference it rather than hard-coding bands,
-- and so a school can later reuse the same scale for gradebook display.
--
-- Access model: mirrors the academic structure exactly (grades/classes/
-- subjects) — can_view_academic() to read, can_manage_academic() to
-- manage. A grading scale is school-configuration catalogue data, not
-- per-learner information, so no is_learner_guardian() clause and no
-- guardian visibility (a guardian sees the resolved code/label already
-- baked into a published report card, never the scale table itself).
--
-- Never hard-deleted (no DELETE policy + FORCE RLS) — active=false is the
-- archive state, identical to every other catalogue table.

create table public.grading_scales (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  name         text not null check (char_length(name) > 0),
  description  text,
  is_default   boolean not null default false,
  active       boolean not null default true,
  created_by   uuid references public.profiles (id) on delete set null,
  updated_by   uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.grading_scales is 'A reusable per-school percentage -> achievement mapping (its bands live in grading_scale_bands). Referenced by report_card_templates. Never hard-deleted — active=false is the archive state.';
comment on column public.grading_scales.is_default is 'At most one active default per school (grading_scales_one_default_per_school) — offered as the pre-selected scale when creating a report-card template.';

create index grading_scales_school_id_idx on public.grading_scales (school_id);
create unique index grading_scales_school_id_name_key on public.grading_scales (school_id, lower(name));
create unique index grading_scales_one_default_per_school on public.grading_scales (school_id) where is_default and active;

create trigger grading_scales_set_updated_at
  before update on public.grading_scales
  for each row execute function public.set_updated_at();

create trigger grading_scales_set_created_updated_by
  before insert or update on public.grading_scales
  for each row execute function public.set_created_updated_by();

-- ---------------------------------------------------------------------------
-- grading_scale_bands — the rows of one scale.

create table public.grading_scale_bands (
  id                uuid primary key default gen_random_uuid(),
  grading_scale_id  uuid not null references public.grading_scales (id) on delete cascade,
  school_id         uuid not null references public.schools (id) on delete cascade,
  code              text not null check (char_length(code) > 0),
  label             text not null check (char_length(label) > 0),
  descriptor        text,
  min_percentage    integer not null check (min_percentage between 0 and 100),
  max_percentage    integer not null check (max_percentage between 0 and 100),
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint grading_scale_bands_range_valid check (min_percentage <= max_percentage)
);

comment on table public.grading_scale_bands is 'One achievement band within a grading scale. Bands within a scale may not overlap (grading_scale_bands_validate) — resolve_achievement() relies on at most one band matching any percentage.';

create index grading_scale_bands_scale_id_idx on public.grading_scale_bands (grading_scale_id);
create index grading_scale_bands_school_id_idx on public.grading_scale_bands (school_id);
create unique index grading_scale_bands_scale_id_code_key on public.grading_scale_bands (grading_scale_id, lower(code));

create trigger grading_scale_bands_set_updated_at
  before update on public.grading_scale_bands
  for each row execute function public.set_updated_at();

-- Closes the FK-doesn't-respect-RLS gap (same pattern as
-- terms_validate_academic_year_school) AND enforces non-overlap of bands
-- within a scale, since a CHECK constraint cannot see sibling rows.
create or replace function public.grading_scale_bands_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scale_school_id uuid;
  v_overlap_count integer;
begin
  select school_id into v_scale_school_id from public.grading_scales where id = new.grading_scale_id;
  if v_scale_school_id is distinct from new.school_id then
    raise exception 'insufficient_privilege: grading_scale_bands.school_id must match the referenced grading_scales.school_id';
  end if;

  select count(*) into v_overlap_count
    from public.grading_scale_bands b
    where b.grading_scale_id = new.grading_scale_id
      and b.id is distinct from new.id
      and new.min_percentage <= b.max_percentage
      and new.max_percentage >= b.min_percentage;
  if v_overlap_count > 0 then
    raise exception 'invalid_argument: band %-%%% overlaps an existing band in this scale', new.min_percentage, new.max_percentage;
  end if;

  return new;
end;
$$;

create trigger grading_scale_bands_validate_trigger
  before insert or update on public.grading_scale_bands
  for each row execute function public.grading_scale_bands_validate();

-- ---------------------------------------------------------------------------
-- resolve_achievement — the single lookup used by the report-card engine.

create or replace function public.resolve_achievement(p_scale_id uuid, p_percentage numeric)
returns table (code text, label text)
language sql
stable
as $$
  select b.code, b.label
  from public.grading_scale_bands b
  where b.grading_scale_id = p_scale_id
    and p_percentage is not null
    and round(p_percentage) >= b.min_percentage
    and round(p_percentage) <= b.max_percentage
  order by b.min_percentage desc
  limit 1
$$;

comment on function public.resolve_achievement(uuid, numeric) is
  'Maps a percentage to its achievement code/label in a grading scale. Returns no row when the scale has no matching band or the percentage is null — callers store NULL code/label in that case, never a fabricated one.';

grant execute on function public.resolve_achievement(uuid, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS

alter table public.grading_scales enable row level security;
alter table public.grading_scales force row level security;
alter table public.grading_scale_bands enable row level security;
alter table public.grading_scale_bands force row level security;

create policy grading_scales_select on public.grading_scales
  for select to authenticated using (public.can_view_academic(school_id));
create policy grading_scales_insert on public.grading_scales
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy grading_scales_update on public.grading_scales
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));

create policy grading_scale_bands_select on public.grading_scale_bands
  for select to authenticated using (public.can_view_academic(school_id));
create policy grading_scale_bands_insert on public.grading_scale_bands
  for insert to authenticated with check (public.can_manage_academic(school_id));
create policy grading_scale_bands_update on public.grading_scale_bands
  for update to authenticated using (public.can_manage_academic(school_id)) with check (public.can_manage_academic(school_id));
create policy grading_scale_bands_delete on public.grading_scale_bands
  for delete to authenticated using (public.can_manage_academic(school_id));

-- grading_scale_bands is the one exception to this schema's no-DELETE rule:
-- a band is a line in an editable configuration table (like a spreadsheet
-- row), not a historical record — removing a mistyped band before the
-- scale is ever used must not require an "archived band" concept the
-- resolve_achievement() lookup would then have to filter. The scale itself
-- is still archive-only.
