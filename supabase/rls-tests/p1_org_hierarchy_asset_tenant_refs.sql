-- Sebetsa — regression coverage for the P1 security remediation
-- (docs/SEBETSA_REMEDIATION_REPORT.md "Remaining Risks" #2 — missing
-- cross-tenant FK-validation triggers on clients/sites/contracts/
-- contract_sites/asset_assignments; fixed in
-- 20260920090100_p1_org_hierarchy_asset_tenant_refs.sql).
--
-- Confirmed by running this file against the pre-fix schema (no trigger
-- on any of these five tables): every SECURITY_FAILURE-labelled INSERT
-- below reproducibly succeeded (a Tenant A row could reference a Tenant B
-- parent) before the fix, and is rejected after it. Also proves the
-- symmetric UPDATE case and that same-tenant references still work
-- (control cases) — a trigger that rejected everything would trivially
-- "pass" the security assertions while breaking the product.
--
--   supabase start
--   cat supabase/rls-tests/p1_org_hierarchy_asset_tenant_refs.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

-- ---------------------------------------------------------------------------
-- Two tenants, each with a full region -> client -> site -> contract chain,
-- plus an asset/employee/team, so every cross-tenant combination named in
-- the remediation brief can be attempted.

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000fd01', 'Tenant A (org-hierarchy tenant refs)', 'active'),
  ('00000000-0000-0000-0000-00000000fe01', 'Tenant B (org-hierarchy tenant refs)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fd02', 'authenticated', 'authenticated', 'admin-fd@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000fd02', '00000000-0000-0000-0000-00000000fd01', 'Admin', 'A', 'admin-fd@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fd02","app_metadata":{"role":"organization_administrator"}}';

insert into public.regions (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000fd03', '00000000-0000-0000-0000-00000000fd01', 'Region A');
insert into public.clients (id, tenant_id, region_id, name) values ('00000000-0000-0000-0000-00000000fd04', '00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fd03', 'Client A');
insert into public.sites (id, tenant_id, client_id, region_id, name, status) values ('00000000-0000-0000-0000-00000000fd05', '00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fd04', '00000000-0000-0000-0000-00000000fd03', 'Site A', 'active');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status) values ('00000000-0000-0000-0000-00000000fd06', '00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fd04', 'CTR-A-001', current_date, 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values ('00000000-0000-0000-0000-00000000fd07', '00000000-0000-0000-0000-00000000fd01', null, 'FD001', 'Tenant', 'A', current_date - 10);
insert into public.teams (id, tenant_id, site_id, name) values ('00000000-0000-0000-0000-00000000fd08', '00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fd05', 'Team A');
insert into public.assets (id, tenant_id, asset_number, name, category, site_id) values ('00000000-0000-0000-0000-00000000fd09', '00000000-0000-0000-0000-00000000fd01', 'AST-A-001', 'Radio A', 'equipment', '00000000-0000-0000-0000-00000000fd05');

reset role;
reset request.jwt.claims;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fe02', 'authenticated', 'authenticated', 'admin-fe@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000fe02', '00000000-0000-0000-0000-00000000fe01', 'Admin', 'B', 'admin-fe@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fe02","app_metadata":{"role":"organization_administrator"}}';

insert into public.regions (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000fe03', '00000000-0000-0000-0000-00000000fe01', 'Region B');
insert into public.clients (id, tenant_id, region_id, name) values ('00000000-0000-0000-0000-00000000fe04', '00000000-0000-0000-0000-00000000fe01', '00000000-0000-0000-0000-00000000fe03', 'Client B');
insert into public.sites (id, tenant_id, client_id, region_id, name, status) values ('00000000-0000-0000-0000-00000000fe05', '00000000-0000-0000-0000-00000000fe01', '00000000-0000-0000-0000-00000000fe04', '00000000-0000-0000-0000-00000000fe03', 'Site B', 'active');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status) values ('00000000-0000-0000-0000-00000000fe06', '00000000-0000-0000-0000-00000000fe01', '00000000-0000-0000-0000-00000000fe04', 'CTR-B-001', current_date, 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values ('00000000-0000-0000-0000-00000000fe07', '00000000-0000-0000-0000-00000000fe01', null, 'FE001', 'Tenant', 'B', current_date - 10);
insert into public.teams (id, tenant_id, site_id, name) values ('00000000-0000-0000-0000-00000000fe08', '00000000-0000-0000-0000-00000000fe01', '00000000-0000-0000-0000-00000000fe05', 'Team B');

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- All remaining attempts run as Tenant A's admin.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fd02","app_metadata":{"role":"organization_administrator"}}';

-- clients.region_id: same-tenant control (already proven by fixture setup
-- above succeeding), then the cross-tenant attack.
do $$
begin
  begin
    insert into public.clients (tenant_id, region_id, name) values ('00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fe03', 'Bad Client A->B region');
    raise exception 'SECURITY_FAILURE: a Tenant A client was created referencing a Tenant B region';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: client.region_id cross-tenant reference is denied (%)', sqlerrm;
  end;
end $$;

-- sites.client_id cross-tenant.
do $$
begin
  begin
    insert into public.sites (tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fe04', 'Bad Site A->B client', 'active');
    raise exception 'SECURITY_FAILURE: a Tenant A site was created referencing a Tenant B client';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: site.client_id cross-tenant reference is denied (%)', sqlerrm;
  end;
end $$;

-- sites.region_id cross-tenant (client is same-tenant and valid; only the
-- region reference is bad — proves both columns are actually checked, not
-- just whichever one happens to run first).
do $$
begin
  begin
    insert into public.sites (tenant_id, client_id, region_id, name, status) values ('00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fd04', '00000000-0000-0000-0000-00000000fe03', 'Bad Site A->B region', 'active');
    raise exception 'SECURITY_FAILURE: a Tenant A site was created referencing a Tenant B region';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: site.region_id cross-tenant reference is denied (%)', sqlerrm;
  end;
end $$;

-- sites: same-tenant reference still succeeds (control — a trigger that
-- rejects everything would falsely "pass" the assertions above).
do $$
declare v_id uuid;
begin
  insert into public.sites (tenant_id, client_id, region_id, name, status) values ('00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fd04', '00000000-0000-0000-0000-00000000fd03', 'Good Site A', 'active') returning id into v_id;
  if v_id is null then raise exception 'FAIL: a legitimate same-tenant site insert was rejected'; end if;
  raise notice 'PASS: a legitimate same-tenant site insert still succeeds';
end $$;

-- contracts.client_id cross-tenant.
do $$
begin
  begin
    insert into public.contracts (tenant_id, client_id, contract_number, start_date, status) values ('00000000-0000-0000-0000-00000000fd01', '00000000-0000-0000-0000-00000000fe04', 'CTR-BAD-001', current_date, 'draft');
    raise exception 'SECURITY_FAILURE: a Tenant A contract was created referencing a Tenant B client';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: contract.client_id cross-tenant reference is denied (%)', sqlerrm;
  end;
end $$;

-- contracts: UPDATE case — an existing, valid Tenant A contract cannot be
-- retargeted onto a Tenant B client either.
do $$
begin
  begin
    update public.contracts set client_id = '00000000-0000-0000-0000-00000000fe04' where id = '00000000-0000-0000-0000-00000000fd06';
    raise exception 'SECURITY_FAILURE: an existing Tenant A contract was retargeted onto a Tenant B client via UPDATE';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: retargeting a contract onto a cross-tenant client via UPDATE is denied (%)', sqlerrm;
  end;
end $$;

-- contract_sites.site_id cross-tenant (contract is Tenant A's own; site is
-- Tenant B's).
do $$
begin
  begin
    insert into public.contract_sites (contract_id, site_id, tenant_id) values ('00000000-0000-0000-0000-00000000fd06', '00000000-0000-0000-0000-00000000fe05', '00000000-0000-0000-0000-00000000fd01');
    raise exception 'SECURITY_FAILURE: a Tenant A contract_site was created referencing a Tenant B site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: contract_sites.site_id cross-tenant reference is denied (%)', sqlerrm;
  end;
end $$;

-- contract_sites.contract_id cross-tenant (site is Tenant A's own;
-- contract is Tenant B's).
do $$
begin
  begin
    insert into public.contract_sites (contract_id, site_id, tenant_id) values ('00000000-0000-0000-0000-00000000fe06', '00000000-0000-0000-0000-00000000fd05', '00000000-0000-0000-0000-00000000fd01');
    raise exception 'SECURITY_FAILURE: a Tenant A contract_site was created referencing a Tenant B contract';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: contract_sites.contract_id cross-tenant reference is denied (%)', sqlerrm;
  end;
end $$;

-- contract_sites: same-tenant reference still succeeds (control).
do $$
begin
  insert into public.contract_sites (contract_id, site_id, tenant_id) values ('00000000-0000-0000-0000-00000000fd06', '00000000-0000-0000-0000-00000000fd05', '00000000-0000-0000-0000-00000000fd01');
  raise notice 'PASS: a legitimate same-tenant contract_sites insert still succeeds';
end $$;

-- ---------------------------------------------------------------------------
-- asset_assignments has no direct client write policy — assign_asset() is
-- the only real path (see its table comment), so the attack is exercised
-- through that RPC, exactly as a real caller would reach it.

do $$
begin
  begin
    perform public.assign_asset('00000000-0000-0000-0000-00000000fd09', p_assigned_to_employee_id => '00000000-0000-0000-0000-00000000fe07');
    raise exception 'SECURITY_FAILURE: a Tenant A asset was assigned to a Tenant B employee via assign_asset()';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: assign_asset() cannot assign to a cross-tenant employee (%)', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    perform public.assign_asset('00000000-0000-0000-0000-00000000fd09', p_assigned_to_team_id => '00000000-0000-0000-0000-00000000fe08');
    raise exception 'SECURITY_FAILURE: a Tenant A asset was assigned to a Tenant B team via assign_asset()';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: assign_asset() cannot assign to a cross-tenant team (%)', sqlerrm;
  end;
end $$;

do $$
begin
  begin
    perform public.assign_asset('00000000-0000-0000-0000-00000000fd09', p_assigned_to_site_id => '00000000-0000-0000-0000-00000000fe05');
    raise exception 'SECURITY_FAILURE: a Tenant A asset was assigned to a Tenant B site via assign_asset()';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: assign_asset() cannot assign to a cross-tenant site (%)', sqlerrm;
  end;
end $$;

-- Control: a legitimate same-tenant assignment still succeeds.
do $$
declare v_result public.assets;
begin
  select * into v_result from public.assign_asset('00000000-0000-0000-0000-00000000fd09', p_assigned_to_employee_id => '00000000-0000-0000-0000-00000000fd07');
  if v_result.status <> 'assigned' then raise exception 'FAIL: a legitimate same-tenant asset assignment did not succeed'; end if;
  raise notice 'PASS: a legitimate same-tenant asset assignment still succeeds';
end $$;

reset role;
reset request.jwt.claims;

rollback;
