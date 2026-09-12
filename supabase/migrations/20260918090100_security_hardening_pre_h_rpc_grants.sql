-- Sebetsa Phase R closure — security hardening pass (§23 of the N-R brief).
--
-- Found while auditing every SECURITY DEFINER function's grants
-- tenant-wide (not just the ones introduced in N-R): five real, callable
-- RPCs predating Phase H (Phase A-C era — user/employee lifecycle
-- management) still carried Postgres's default PUBLIC/anon EXECUTE grant,
-- because the "explicit revoke from public/anon, grant only to
-- authenticated" discipline Phase H established wasn't retroactively
-- applied to functions that already existed at the time.
--
-- Verified NOT currently exploitable: every one of these already checks
-- `auth.uid()`/`auth.jwt()`-derived authorization internally, and an
-- unauthenticated `anon` caller has neither, so today's behavior is a
-- clean permission-denied exception, not a data leak. But per the Phase H
-- lesson itself — "never assume `revoke from public` alone means a
-- function is inaccessible; explicitly inspect effective grants" — relying
-- on that internal check alone, rather than also closing the grant, is
-- exactly the anti-pattern that lesson exists to prevent. Fixing it here
-- as defense-in-depth, not because of a demonstrated exploit.

revoke execute on function public.admin_create_user(text, text, text, text, public.user_role, uuid) from public, anon;
revoke execute on function public.admin_update_user_role(uuid, public.user_role) from public, anon;
revoke execute on function public.terminate_employee(uuid, date) from public, anon;
revoke execute on function public.reactivate_employee(uuid) from public, anon;
revoke execute on function public.provision_employee_login(uuid, public.user_role, text) from public, anon;

grant execute on function public.admin_create_user(text, text, text, text, public.user_role, uuid) to authenticated;
grant execute on function public.admin_update_user_role(uuid, public.user_role) to authenticated;
grant execute on function public.terminate_employee(uuid, date) to authenticated;
grant execute on function public.reactivate_employee(uuid) to authenticated;
grant execute on function public.provision_employee_login(uuid, public.user_role, text) to authenticated;
