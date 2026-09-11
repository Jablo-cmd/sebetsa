-- Sebetsa Phase C — Multi-Tenant Foundation
-- Row Level Security base: every query against a tenant-scoped table is
-- filtered to the caller's own tenant, enforced in Postgres itself.
-- Pattern reused verbatim from Funda360
-- (supabase/migrations/20260802125403_row_level_security.sql).

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

-- Platform-level roles bypass tenant scoping. Reads the `role` JWT claim
-- from app_metadata (fails closed until it is set).
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'platform_administrator'
$$;

comment on function public.is_platform_admin() is
  'True for platform admins once app_metadata.role is set on the user. Fails closed (false) until then.';

alter table public.organizations enable row level security;
alter table public.organizations force row level security;

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

-- organizations: readable by members of that org, or a platform admin.
-- No insert/update/delete policy yet — org onboarding is service_role only
-- until a deliberate onboarding flow is built.
create policy organizations_select_within_tenant_or_platform_admin
  on public.organizations
  for select
  to authenticated
  using (
    id = public.current_tenant_id()
    or public.is_platform_admin()
  );

-- profiles: a user always sees their own row; additionally sees every
-- profile in their tenant, or every profile if a platform admin.
create policy profiles_select_own_or_tenant_or_platform_admin
  on public.profiles
  for select
  to authenticated
  using (
    id = auth.uid()
    or tenant_id = public.current_tenant_id()
    or public.is_platform_admin()
  );

-- Self-service profile editing only.
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());
