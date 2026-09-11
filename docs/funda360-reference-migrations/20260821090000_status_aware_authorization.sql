-- Status-aware authorization — close the deactivated-user access gap
--
-- Finding: current_tenant_id() and is_platform_admin() are the two choke-
-- point functions every tenant-scoped RLS policy in the schema is built on
-- (see 20260802125403_row_level_security.sql), and neither one checks
-- profiles.status. TenantGate.tsx (client-side) blocks a deactivated
-- user's *UI*, but nothing ever re-validates their live status at the data
-- layer — a deactivated Teacher or Principal's still-valid Supabase
-- session (jwt_expiry=3600s, refresh-token rotation enabled, so a browser
-- tab left open keeps refreshing indefinitely) retains full, unrestricted
-- RLS-authorized access to every tenant-scoped table until they happen to
-- lose that session some other way. A direct API call bypassing the React
-- app would sail through untouched. This is a genuine authorization gap,
-- not merely UI polish, and the fix is to extend the same two functions
-- everything already depends on rather than invent a second mechanism.
--
-- Deliberately NOT touched: `id = auth.uid()` branches (e.g.
-- profiles_select's own-row clause) stay status-independent so a
-- deactivated user can still fetch their own profile row — TenantGate
-- needs exactly that to render "Account deactivated" instead of a blank
-- failure. Only *tenant-wide* and *platform-wide* authorization is gated.

create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.profiles where id = auth.uid() and status = 'active'
$$;

comment on function public.current_tenant_id() is
  'Resolves the calling user''s tenant_id from profiles, but ONLY while their profile is active — inactive/suspended profiles resolve to NULL here, which correctly fails every tenant-scoped policy built on this function (school_id = current_tenant_id() can never match NULL). SECURITY DEFINER to avoid recursive RLS on profiles.';

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('super_administrator', 'platform_administrator')
    and exists (select 1 from public.profiles where id = auth.uid() and status = 'active')
$$;

comment on function public.is_platform_admin() is
  'True for super/platform admins, but ONLY while their own profile is active — a deactivated platform admin loses the all-tenants bypass immediately, not just in the UI. SECURITY DEFINER for the same profiles-lookup reason as current_tenant_id(); the profiles_select policy''s id=auth.uid() branch would also satisfy this non-recursively, but SECURITY DEFINER keeps both functions consistent and independent of policy evaluation order.';
