-- Attendance — add 'excused' status
--
-- Pilot preparation surfaced a genuine gap: the original attendance_status
-- enum (20260817120000_attendance.sql) only modelled present/absent/late,
-- matching the one pasted daily-register example that sprint was built
-- from. A real school register also needs to distinguish an unexcused
-- absence from one the school has already approved (a medical note, a
-- planned leave of absence) — the two must not count the same way toward
-- an attendance-percentage calculation. This migration only adds the new
-- enum value; it does not touch any existing row, policy, or constraint —
-- every attendance_records row written before this migration keeps its
-- original status untouched.
--
-- Postgres requires ALTER TYPE ... ADD VALUE to run outside any
-- transaction block that also uses the new value, but permits it as its
-- own standalone statement (the case here) without incident on PG 17.

alter type public.attendance_status add value 'excused';
