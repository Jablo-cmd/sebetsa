-- School announcements (FND-COM-003)
--
-- A school-wide broadcast: school_owner/principal post a title+body to one
-- of three audiences (all_staff, all_guardians, or everyone), and every
-- matching, active profile in the tenant gets a real notifications row —
-- the exact same SECURITY DEFINER fan-out pattern
-- attendance_records_check_alert() (FND-ATT-002) just established, applied
-- here to a broadcast instead of a per-learner event. Posting reuses
-- `school.manage` / can_manage_school() wholesale rather than inventing a
-- new communication.manage_announcements permission — that permission's
-- role set (school_owner, principal, platform admin) is already exactly
-- the set an announcement-posting permission would need, and
-- can_manage_school() already gates the closest existing analog
-- (school-profile editing, logo upload).
--
-- Visibility is audience-scoped, not just tenant-scoped: a guardian must
-- never see an all_staff announcement (which could reasonably reference
-- internal operational detail) and vice versa. The same
-- `coalesce(auth.jwt()->'app_metadata'->>'role','') in ('parent','guardian')`
-- idiom parent_portal_v1's own reference-data guardian policies already use
-- distinguishes the two.

create type public.announcement_audience as enum ('all_staff', 'all_guardians', 'everyone');

create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null references public.schools (id) on delete cascade,
  title       text not null check (char_length(title) > 0),
  body        text not null check (char_length(body) > 0),
  audience    public.announcement_audience not null default 'everyone',
  active      boolean not null default true,
  created_by  uuid references public.profiles (id) on delete set null,
  updated_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.announcements is 'School-wide broadcasts. Never hard-deleted — active=false is the archive state, same pattern as every other table in this schema. Posting fans out a real notifications row to every matching, active profile via announcements_notify_recipients().';

create index announcements_school_id_idx on public.announcements (school_id);

create trigger announcements_set_updated_at
  before update on public.announcements
  for each row
  execute function public.set_updated_at();

create trigger announcements_set_created_updated_by
  before insert or update on public.announcements
  for each row
  execute function public.set_created_updated_by();

-- ---------------------------------------------------------------------------
-- RLS

alter table public.announcements enable row level security;
alter table public.announcements force row level security;

-- can_manage_school() sees every announcement in their own tenant
-- regardless of audience, not just the ones addressed to them — a
-- principal reviewing/archiving posts needs to see all of them, including
-- an all_guardians-only one they or a colleague posted. This also matters
-- structurally: INSERT ... RETURNING re-checks the SELECT policy on the
-- returned row, so without this clause a manager posting an
-- all_guardians-only announcement couldn't even see their own INSERT's
-- RETURNING result (they're not a guardian) and the statement would fail.
create policy announcements_select on public.announcements
  for select to authenticated using (
    (
      school_id = public.current_tenant_id()
      and (
        public.can_manage_school(school_id)
        or audience = 'everyone'
        or (audience = 'all_guardians' and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('parent', 'guardian'))
        or (audience = 'all_staff' and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('parent', 'guardian'))
      )
    )
    or public.is_platform_admin()
  );

create policy announcements_insert on public.announcements
  for insert to authenticated with check (public.can_manage_school(school_id));

create policy announcements_update on public.announcements
  for update to authenticated using (public.can_manage_school(school_id)) with check (public.can_manage_school(school_id));

-- No DELETE policy — combined with FORCE ROW LEVEL SECURITY, hard delete is
-- impossible, same as every other table in this schema.

-- ---------------------------------------------------------------------------
-- Notification fan-out

create or replace function public.announcements_notify_recipients()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient record;
  v_link_path text;
begin
  for v_recipient in
    select id, role from public.profiles
    where tenant_id = new.school_id
      and status = 'active'
      and id is distinct from new.created_by
      and (
        new.audience = 'everyone'
        or (new.audience = 'all_guardians' and role in ('parent', 'guardian'))
        or (new.audience = 'all_staff' and role not in ('parent', 'guardian'))
      )
  loop
    v_link_path := case when v_recipient.role in ('parent', 'guardian') then '/parent/announcements' else '/announcements' end;
    perform public.create_notification(
      v_recipient.id,
      'announcement',
      new.title,
      new.body,
      new.school_id,
      'announcements',
      new.id,
      v_link_path
    );
  end loop;

  return new;
end;
$$;

comment on function public.announcements_notify_recipients() is
  'AFTER INSERT trigger on announcements — notifies every active profile in the audience (via create_notification()), routing each recipient''s link_path to the layout their role actually lands in (/parent/announcements vs /announcements), same split NotificationBell''s own `to` prop already needs. Excludes the poster themselves. returns trigger, so (like audit_log_from_trigger()/attendance_records_check_alert()) it cannot be invoked directly via RPC regardless of GRANT status.';

create trigger announcements_notify_recipients_trigger
  after insert on public.announcements
  for each row
  execute function public.announcements_notify_recipients();
