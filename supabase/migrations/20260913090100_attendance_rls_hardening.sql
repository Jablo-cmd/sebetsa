-- Sebetsa Phase I — attendance_records RLS hardening.
--
-- Two pre-existing gaps closed here, matching the Phase H precedent
-- (leave_requests had the identical over-broad SELECT policy, fixed in
-- 20260912090200):
--
-- 1. attendance_records_select_within_tenant let ANY tenant member read
--    every employee's attendance — narrowed to the operational-management
--    tier or the employee's own record, same shape as leave_requests.
-- 2. There was no self-service write path at all — an ordinary employee
--    could not clock themself in/out via direct table access. Self-service
--    clock actions are handled by SECURITY DEFINER RPCs (see the next
--    migration), not by widening this table's RLS — the RPCs enforce the
--    narrow "only your own open/most-recent record" rules an RLS policy
--    can't express as precisely.

drop policy if exists attendance_records_select_within_tenant on public.attendance_records;

create policy attendance_records_select_own_or_broad on public.attendance_records for select to authenticated
  using (
    public.can_manage_operations(tenant_id)
    or exists (select 1 from public.employees e where e.id = attendance_records.employee_id and e.profile_id = auth.uid())
  );

comment on table public.attendance_records is
  'A separate fact from the schedule (never derived by mutating a shifts row). Self-service clock-in/out/break/correction-request goes through SECURITY DEFINER RPCs (clock_in/clock_out/start_break/end_break/request_attendance_correction), never direct table writes — attendance_records_write_by_manager remains for the operational-management tier''s direct corrections/manual entries.';
