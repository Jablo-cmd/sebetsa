-- Sebetsa Phase D — Organisation Onboarding
-- The base RLS migration (20260911100200) deliberately left organizations
-- writable only by service_role. A platform admin onboarding a brand-new
-- tenant (Step 4 of the platform) is a real, load-bearing flow, so this adds
-- the missing INSERT policy rather than leaving onboarding broken.

create policy organizations_insert_by_platform_admin
  on public.organizations
  for insert
  to authenticated
  with check (public.is_platform_admin());

comment on policy organizations_insert_by_platform_admin on public.organizations is
  'Only platform admins create new tenant roots — a tenant-scoped user already belongs to one.';
