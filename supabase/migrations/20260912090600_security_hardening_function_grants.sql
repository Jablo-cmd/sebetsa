-- Sebetsa — production-hardening fix discovered during Phase H hosted
-- verification, not introduced by Phase H itself.
--
-- Supabase auto-grants EXECUTE on every new `public` schema function to
-- anon/authenticated/service_role at creation time. `revoke execute ...
-- from public` (used throughout this codebase, including Phase C's
-- write_audit_log/create_notification and Phase H's
-- seed_default_leave_types) only revokes the implicit PUBLIC pseudo-role —
-- it does NOT undo the separate, already-granted authenticated/anon
-- privilege. Confirmed directly against hosted: despite their own doc
-- comments explicitly saying "not granted to authenticated", all three
-- functions below were callable by any authenticated user with zero
-- internal permission check:
--
--   write_audit_log       — any authenticated user could insert arbitrary
--                            audit_log rows (fake tenant_id/actor/action/
--                            before/after), undermining the audit trail's
--                            integrity across every domain.
--   create_notification    — any authenticated user could send arbitrary
--                            notifications to any recipient (including
--                            cross-tenant) with fabricated content and
--                            link_path — a phishing/spoofing vector.
--   seed_default_leave_types (Phase H) — any authenticated user could
--                            reseed leave types into any tenant_id,
--                            including one they don't belong to.
--
-- Purely a privilege reduction — cannot break any legitimate call path,
-- since a SECURITY DEFINER function invoked from inside another SECURITY
-- DEFINER function executes under the definer's own privileges, not the
-- original caller's grants.

revoke execute on function public.write_audit_log(uuid, uuid, text, text, uuid, jsonb, jsonb) from authenticated, anon;
revoke execute on function public.create_notification(uuid, text, text, text, uuid, text, uuid, text) from authenticated, anon;
revoke execute on function public.seed_default_leave_types(uuid) from authenticated, anon;

-- ---------------------------------------------------------------------------
-- Fallout from the revoke above, caught by re-running the leave RLS suite
-- locally before this migration ever reached hosted: shifts_leave_conflict_
-- guard() (20260912090500_leave_rpcs.sql) is a plain SECURITY INVOKER
-- trigger — unlike every other *_audit_log trigger in this codebase
-- (audit_log_from_trigger() is SECURITY DEFINER), it was missing that
-- clause, so its internal `perform public.write_audit_log(...)` call on a
-- successful leave-conflict override executed as the calling session's own
-- role (authenticated) rather than the function owner — which the revoke
-- above now correctly denies. Redefining it SECURITY DEFINER (matching
-- every other audit-writing trigger in the codebase) restores the
-- intended behavior without reopening the hole the revoke just closed.
create or replace function public.shifts_leave_conflict_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conflict boolean;
  v_override boolean;
begin
  select exists (
    select 1 from public.employee_availability_exceptions eae
    where eae.employee_id = new.employee_id
      and eae.leave_request_id is not null
      and eae.is_available = false
      and eae.exception_date >= new.starts_at::date
      and eae.exception_date <= new.ends_at::date
  ) into v_conflict;

  if not v_conflict then
    return new;
  end if;

  v_override := coalesce(current_setting('app.override_leave_conflict', true), '') = 'true';

  if not v_override then
    raise exception 'leave_conflict: employee % has approved leave overlapping this shift; pass override_leave_conflict to proceed', new.employee_id;
  end if;

  if not public.can_approve_leave(new.tenant_id) then
    raise exception 'insufficient_privilege: overriding a leave conflict requires leave.approve';
  end if;

  perform public.write_audit_log(
    new.tenant_id, auth.uid(), 'leave_schedule_override', 'shifts', coalesce(new.id, gen_random_uuid()),
    null, jsonb_build_object('employee_id', new.employee_id, 'starts_at', new.starts_at, 'ends_at', new.ends_at)
  );

  return new;
end;
$$;
