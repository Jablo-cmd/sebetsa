-- Milestone 3 — Multi-Tenant Foundation
-- Row Level Security: every query against a tenant-scoped table is
-- filtered to the caller's own tenant, enforced in Postgres itself (not
-- just in application code) — the last line of defense against a bug in
-- the client ever leaking one school's data to another.
--
-- `current_tenant_id()` looks the caller's tenant up from `profiles`
-- rather than a JWT claim, so it works immediately with nothing extra to
-- configure. It's SECURITY DEFINER so the lookup runs with the function
-- owner's privileges — otherwise a policy on `profiles` calling a function
-- that itself queries `profiles` would recurse into the same RLS check
-- it's trying to evaluate.
create or replace function public.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select tenant_id from public.profiles where id = auth.uid()
$$;

comment on function public.current_tenant_id() is
  'Resolves the calling user''s tenant_id from profiles. SECURITY DEFINER to avoid recursive RLS on profiles.';

-- Platform-level roles (Super Admin, Platform Admin — RBAC spec §6, "All
-- tenants" scope) bypass tenant scoping. This reads the `role` JWT claim
-- from app_metadata, which Supabase always includes in the token once it's
-- set on the user (see supabase/seed.sql) — no extra configuration
-- required. Until it's set, this returns false (fails closed) — see
-- src/features/auth/utils/toAuthenticatedUser.ts for the client-side half
-- of the same mechanism.
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('super_administrator', 'platform_administrator')
$$;

comment on function public.is_platform_admin() is
  'True for super/platform admins once app_metadata.role is set on the user. Fails closed (false) until then.';

alter table public.schools enable row level security;
alter table public.schools force row level security;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

-- schools: readable by members of that school, or a platform admin.
-- No insert/update/delete policy is defined yet — school onboarding and
-- settings management is a future epic; for now only the Postgres
-- `service_role` (which bypasses RLS entirely) can write these rows.
create policy schools_select_within_tenant_or_platform_admin
  on public.schools
  for select
  to authenticated
  using (
    id = public.current_tenant_id()
    or public.is_platform_admin()
  );

-- profiles: a user always sees their own row; additionally sees every
-- profile in their tenant (principals/HR need staff directories later) or,
-- if a platform admin, every profile.
create policy profiles_select_own_or_tenant_or_platform_admin
  on public.profiles
  for select
  to authenticated
  using (
    id = auth.uid()
    or tenant_id = public.current_tenant_id()
    or public.is_platform_admin()
  );

-- Self-service profile editing only — no one edits another user's profile
-- through this policy (staff management is a future epic with its own,
-- more deliberate authorization rules).
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
