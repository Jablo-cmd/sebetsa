-- Platform Admin School Onboarding
--
-- `schools` has had SELECT (Milestone 3) and UPDATE (Milestone 4) policies,
-- but no INSERT policy was ever added — onboarding a brand-new school was
-- left to service_role/manual SQL. That's a real gap: platform
-- administrators intentionally carry tenant_id = NULL (they operate across
-- tenants, see is_platform_admin()/current_tenant_id()) and have no other
-- path to create the first school a tenant needs before any school-scoped
-- record (academic years, grades, learners, employees, ...) can exist.
--
-- This grants INSERT to platform admins only. Tenant-scoped roles
-- (school_owner, principal, etc.) never get it — they already belong to an
-- existing school by definition, and onboarding a *new* school is a
-- platform-level action, mirroring can_manage_school()'s existing shape.
create policy schools_insert_by_platform_admin
  on public.schools
  for insert
  to authenticated
  with check (public.is_platform_admin());
