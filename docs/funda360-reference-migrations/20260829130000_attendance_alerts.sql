-- Persisted, notification-integrated attendance alerts (FND-ATT-002)
--
-- learnerAlerts.ts already computes an "attendance below threshold" badge,
-- but only client-side, only when someone happens to open that learner's
-- profile page — nobody is proactively told. This migration adds the
-- server-side half: when a learner is marked 'absent' for 3 consecutive
-- school days (the 3rd-from-latest, 2nd-from-latest, and latest
-- attendance_records rows all 'absent' — "consecutive school days", not
-- consecutive calendar days, since rows only exist for days a register was
-- actually taken), each of the learner's active guardians gets a real
-- notifications row via create_notification(), reusing the exact
-- SECURITY DEFINER insertion point FND-COM-001 built.
--
-- Fires-once-per-streak, not once-per-day-of-the-streak: rather than
-- guessing "is this the first row to reach 3" from array position (which
-- breaks under a multi-row batched INSERT — Postgres queues AFTER ROW
-- triggers and fires them all at the end of the statement, by which point
-- every row in that same statement is already visible to each trigger
-- invocation, so a position-based guard would fire once per row in the
-- batch instead of once per streak), idempotency is checked against
-- actually-persisted state: walk backward from the latest record to find
-- the current unbroken absent streak's start date, then skip if a
-- notification already exists referencing any record on/after that date.
-- This is correct regardless of insert batching or ordering, and a streak
-- that breaks (a present/late/excused day) and later re-reaches 3 fires
-- again, correctly treated as a new episode (its streak-start date moves
-- forward past the break, so the old notification no longer counts as
-- "within this streak").
--
-- Fires on INSERT OR UPDATE but only when NEW.status = 'absent' — matches
-- how attendance is actually written (attendanceService.markRegister does
-- a single class-wide upsert, so a correction that flips a day to 'absent'
-- after the fact still triggers correctly; a correction that flips a day
-- AWAY from 'absent' never needs to raise anything).
--
-- Recipients are the learner's guardians, not staff: notifications.RLS is
-- recipient-only with no broad staff-visibility tier (see FND-COM-001's own
-- documented reasoning), and "tell the parent their child has been away 3
-- days running" is the concrete, immediately actionable version of this
-- alert a school actually wants. A staff-facing surfacing of the same
-- signal already exists today via learnerAlerts.ts on the learner profile
-- (does not require duplicating it here) and via the Attendance Report page.

create or replace function public.attendance_records_check_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_streak_length int := 0;
  v_streak_start date;
  v_already_notified boolean;
  v_learner_name text;
  v_rec record;
  v_guardian record;
begin
  if new.status is distinct from 'absent' then
    return new;
  end if;

  -- Walk backward from the most recent record to find the current
  -- unbroken 'absent' streak's length and start date. Capped at 60 rows —
  -- comfortably longer than a term's worth of school days, so a real
  -- streak is never truncated, while a runaway loop on anomalous data is
  -- structurally impossible.
  for v_rec in
    select status, attendance_date from public.attendance_records
    where learner_id = new.learner_id
    order by attendance_date desc
    limit 60
  loop
    exit when v_rec.status is distinct from 'absent';
    v_streak_length := v_streak_length + 1;
    v_streak_start := v_rec.attendance_date;
  end loop;

  if v_streak_length < 3 then
    return new;
  end if;

  select exists (
    select 1
    from public.notifications n
    join public.attendance_records ar on ar.id = n.related_entity_id
    where n.type = 'attendance_alert' and ar.learner_id = new.learner_id and ar.attendance_date >= v_streak_start
  ) into v_already_notified;

  if v_already_notified then
    return new;
  end if;

  select (first_name || ' ' || last_name) into v_learner_name from public.learners where id = new.learner_id;

  for v_guardian in
    select guardian_profile_id from public.learner_guardians where learner_id = new.learner_id and active
  loop
    perform public.create_notification(
      v_guardian.guardian_profile_id,
      'attendance_alert',
      'Attendance alert',
      coalesce(v_learner_name, 'Your child') || ' has been marked absent for 3 consecutive school days.',
      new.school_id,
      'attendance_records',
      new.id,
      '/parent/children/' || new.learner_id::text
    );
  end loop;

  return new;
end;
$$;

comment on function public.attendance_records_check_alert() is
  'AFTER INSERT OR UPDATE trigger on attendance_records — notifies each of the learner''s active guardians (via create_notification()) exactly once when a 3-consecutive-absence streak is first reached. returns trigger, so (like audit_log_from_trigger()) it cannot be invoked directly via RPC regardless of GRANT status — no explicit revoke needed, same reasoning already documented for audit_log_from_trigger().';

create trigger attendance_records_check_alert_trigger
  after insert or update on public.attendance_records
  for each row
  execute function public.attendance_records_check_alert();
