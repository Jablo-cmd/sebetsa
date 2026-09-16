-- Sebetsa — P2 hygiene fix, discovered during this sprint's §11 SECURITY
-- DEFINER/grants audit (docs/PRODUCTION_READINESS_AUDIT.md MEDIUM finding,
-- carried forward unfixed by the prior remediation pass): the boolean
-- permission-helper functions never received the explicit
-- `revoke ... from public, anon` the Phase H lesson established for every
-- other SECURITY DEFINER function in this codebase — they only ever got a
-- `grant ... to authenticated`, relying on the implicit absence of a
-- public/anon grant rather than an explicit revoke.
--
-- Low actual risk (each function only returns a boolean derived from
-- auth.uid()/auth.jwt(), which resolve to null/empty for an anon caller,
-- so the boolean itself leaks nothing), but it is the same gap-class this
-- project explicitly said it closed — worth closing for real rather than
-- leaving as a known, documented exception. Purely additive; does not
-- change any function's behavior for any already-authorized caller.

revoke execute on function public.can_manage_profiles(uuid) from public, anon;
revoke execute on function public.can_assign_role(public.user_role, public.user_role) from public, anon;
revoke execute on function public.can_manage_org_structure(uuid) from public, anon;
revoke execute on function public.can_manage_operations(uuid) from public, anon;
revoke execute on function public.can_manage_employees(uuid) from public, anon;
revoke execute on function public.can_manage_leave(uuid) from public, anon;
revoke execute on function public.can_approve_leave(uuid) from public, anon;
revoke execute on function public.can_view_leave_broad(uuid) from public, anon;
