-- Sebetsa Phase E — RLS / tenant-isolation checks for the organisation
-- hierarchy (regions, clients, sites, contracts).
--
-- Not wired into an automated CI job yet (Funda360's full pgTAP-style
-- harness — auth stubs, fixtures, run.sh — was archived as reference at
-- docs/funda360-reference-other/rls-tests/ rather than rebuilt this phase;
-- that's Phase K scope). This is a real, repeatable psql script exercising
-- the actual RLS policies against a local Postgres, not a mock — run it
-- with:
--
--   supabase start
--   cat supabase/rls-tests/org_hierarchy.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- Every check either prints its own PASS notice or raises an exception
-- (visible as a hard psql error), so a clean run with no ERROR lines is a
-- pass. Wrapped in one transaction that always rolls back — never leaves
-- fixture data behind.

begin;

-- ---------------------------------------------------------------------------
-- Fixtures: two tenants, one org_administrator per tenant, one 'employee'
-- (no org_structure.manage) in tenant A.
insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000000a1', 'Org A', 'active'),
  ('00000000-0000-0000-0000-0000000000b1', 'Org B', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'admin-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'admin-b@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'employee-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1', 'Admin', 'A', 'admin-a@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b1', 'Admin', 'B', 'admin-b@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a1', 'Employee', 'A', 'employee-a@example.com', 'employee', 'active');

-- ---------------------------------------------------------------------------
-- CREATE + READ: Org A's admin builds the full hierarchy.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a2","app_metadata":{"role":"organization_administrator"}}';

insert into public.regions (id, tenant_id, name)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'Gauteng');

insert into public.clients (id, tenant_id, region_id, name)
values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 'ACME Property Group');

insert into public.sites (id, tenant_id, client_id, region_id, name)
values ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Sandton Mall');

insert into public.contracts (id, tenant_id, client_id, contract_number, start_date)
values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000002', 'SRV-2026-001', current_date);

insert into public.contract_sites (contract_id, site_id, tenant_id)
values ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000a1');

do $$
declare v_count int;
begin
  select count(*) into v_count from public.regions where id = '00000000-0000-0000-0000-000000000001';
  if v_count != 1 then raise exception 'FAIL: orgA admin cannot read own region'; end if;
  select count(*) into v_count from public.clients where id = '00000000-0000-0000-0000-000000000002';
  if v_count != 1 then raise exception 'FAIL: orgA admin cannot read own client'; end if;
  select count(*) into v_count from public.sites where id = '00000000-0000-0000-0000-000000000003';
  if v_count != 1 then raise exception 'FAIL: orgA admin cannot read own site'; end if;
  select count(*) into v_count from public.contracts where id = '00000000-0000-0000-0000-000000000004';
  if v_count != 1 then raise exception 'FAIL: orgA admin cannot read own contract'; end if;
  raise notice 'PASS: orgA admin created and reads the full hierarchy';
end $$;

-- UPDATE: audit trail exists after an update (regions_audit_log trigger).
update public.regions set code = 'GP' where id = '00000000-0000-0000-0000-000000000001';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log
    where entity_table = 'regions' and entity_id = '00000000-0000-0000-0000-000000000001' and action = 'update_regions';
  if v_count < 1 then raise exception 'FAIL: region update was not audit-logged'; end if;
  raise notice 'PASS: region update produced an audit_log row';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- TENANT ISOLATION: Org B's admin sees none of Org A's rows.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.regions where tenant_id = '00000000-0000-0000-0000-0000000000a1';
  if v_count != 0 then raise exception 'SECURITY_FAILURE: orgB sees orgA regions'; end if;
  select count(*) into v_count from public.clients where tenant_id = '00000000-0000-0000-0000-0000000000a1';
  if v_count != 0 then raise exception 'SECURITY_FAILURE: orgB sees orgA clients'; end if;
  select count(*) into v_count from public.sites where tenant_id = '00000000-0000-0000-0000-0000000000a1';
  if v_count != 0 then raise exception 'SECURITY_FAILURE: orgB sees orgA sites'; end if;
  select count(*) into v_count from public.contracts where tenant_id = '00000000-0000-0000-0000-0000000000a1';
  if v_count != 0 then raise exception 'SECURITY_FAILURE: orgB sees orgA contracts'; end if;
  raise notice 'PASS: orgB admin sees zero of orgA''s hierarchy rows';
end $$;

-- UNAUTHORIZED WRITE: Org B admin cannot insert a row tagged as Org A.
do $$
begin
  begin
    insert into public.regions (tenant_id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Cross-tenant-region');
    raise exception 'SECURITY_FAILURE: orgB admin cross-tenant region insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant region insert blocked by RLS (%)', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    insert into public.clients (tenant_id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Cross-tenant-client');
    raise exception 'SECURITY_FAILURE: orgB admin cross-tenant client insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant client insert blocked by RLS (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- UNAUTHORIZED ROLE: an 'employee' in Org A holds neither org_structure.view
-- nor org_structure.manage (see rolePermissions.ts — employee is
-- deliberately minimal). Corrected 2026-09-19 as part of the production-
-- readiness audit's C-2 remediation (docs/PRODUCTION_READINESS_AUDIT.md):
-- this assertion previously expected employee to read the region, which
-- was only true because regions_select_within_tenant had no role check at
-- all (the bug being fixed) — not because employee was ever meant to see
-- org-hierarchy data.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a3","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.regions where id = '00000000-0000-0000-0000-000000000001';
  if v_count != 0 then raise exception 'SECURITY_FAILURE: employee (no org_structure.view) read a region, got % rows', v_count; end if;
  raise notice 'PASS: employee (no org_structure.view) correctly sees zero regions';
end $$;

do $$
begin
  begin
    insert into public.regions (tenant_id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Employee-created-region');
    raise exception 'SECURITY_FAILURE: employee role created a region';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: employee role blocked from creating a region (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
