-- Milestone 4 — School Administration Core
-- Enhances `schools` for the School Profile feature and opens up
-- (tenant-scoped, role-gated) write access that Milestone 3 deliberately
-- left to service_role only.

-- `address` was a single free-text field; the School Profile page needs
-- physical vs. postal separately, so rename rather than leave a redundant
-- column alongside a new one.
alter table public.schools rename column address to physical_address;
alter table public.schools add column postal_address text;
alter table public.schools add column principal_name text;

comment on column public.schools.physical_address is 'Street/campus address.';
comment on column public.schools.postal_address is 'Mailing address, if different from the physical address.';
comment on column public.schools.principal_name is 'Free-text principal name for display — not a link to a profiles row.';

-- Same elevated-role set as ROLE_PERMISSIONS['school.manage'] in
-- src/features/rbac/constants/rolePermissions.ts (school_owner, principal,
-- plus platform-level roles) — kept in sync manually since role data lives
-- in the JWT, not a table RLS can join against.
create or replace function public.can_manage_school(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('school_owner', 'principal')
    )
    or public.is_platform_admin()
$$;

comment on function public.can_manage_school(uuid) is
  'True for school_owner/principal of the target school, or any platform admin. Mirrors the app-level school.manage permission.';

create policy schools_update_by_management_or_platform_admin
  on public.schools
  for update
  to authenticated
  using (public.can_manage_school(id))
  with check (public.can_manage_school(id));