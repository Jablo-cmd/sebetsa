-- Sebetsa Phase H — final hardening pass, discovered during the closure
-- security audit: all 8 Leave RPCs carry the same Supabase auto-grant
-- default-privilege gap as write_audit_log/create_notification (see
-- 20260912090600) — anon holds EXECUTE alongside authenticated.
--
-- Unlike write_audit_log/create_notification, these 8 are NOT actually
-- exploitable by an anonymous caller: every one resolves identity via
-- auth.uid() and/or auth.jwt()->app_metadata->>'role', both of which are
-- null/empty for an anon request, so every internal permission check
-- (can_approve_leave/can_manage_leave, the employee.profile_id = auth.uid()
-- self-service clause, or a plain "not_found" on a null-keyed lookup)
-- fails closed already. This migration is pure defense-in-depth — the
-- explicit production-readiness requirement is "anon cannot execute
-- privileged functions" as a stated grant, not merely as an emergent
-- behavior of the function body.

revoke execute on function public.submit_leave_request(uuid, uuid, date, date, boolean, text, text, text) from anon;
revoke execute on function public.cancel_leave_request(uuid) from anon;
revoke execute on function public.approve_leave_request(uuid, text) from anon;
revoke execute on function public.reject_leave_request(uuid, text) from anon;
revoke execute on function public.revoke_leave_request(uuid, text) from anon;
revoke execute on function public.adjust_leave_balance(uuid, uuid, int, numeric, text) from anon;
revoke execute on function public.recompute_leave_balance(uuid, uuid, int) from anon;
revoke execute on function public.get_leave_affected_shifts(uuid) from anon;
