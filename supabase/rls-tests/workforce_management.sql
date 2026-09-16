-- Sebetsa Phase F — RLS / cross-tenant-relationship checks for the
-- workforce hierarchy (departments, positions, employees, teams,
-- team_members, site_assignments).
--
-- Same pattern as supabase/rls-tests/org_hierarchy.sql — a real, repeatable
-- psql script against actual RLS policies and triggers, not a mock. Run:
--
--   supabase start
--   cat supabase/rls-tests/workforce_management.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- Covers what org_hierarchy.sql doesn't: cross-tenant *relationship*
-- rejection (an employee whose department/position/site points at another
-- tenant's row, not just an employee tagged with another tenant's
-- tenant_id), audit coverage for the workforce tables, and that write
-- access for teams/site_assignments is operational-tier
-- (organization_administrator/operations_manager/regional_manager/
-- site_manager/supervisor via can_manage_operations()) while
-- departments/positions stay org-structure-tier
-- (organization_administrator/operations_manager/hr_user via
-- can_manage_org_structure()). One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000000a1', 'Org A', 'active'),
  ('00000000-0000-0000-0000-0000000000b1', 'Org B', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'admin-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a1', 'Admin', 'A', 'admin-a@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a2","app_metadata":{"role":"organization_administrator"}}';

-- Org A structure
insert into public.departments (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000001001', '00000000-0000-0000-0000-0000000000a1', 'Operations A');
insert into public.positions (id, tenant_id, department_id, title) values
  ('00000000-0000-0000-0000-000000002001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000001001', 'Cleaner A');
insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000003001', '00000000-0000-0000-0000-0000000000a1', 'Client A');
-- status explicitly 'active' (not the default 'onboarding') — this site
-- receives a real site_assignment below, and P0 remediation
-- (docs/PRODUCTION_READINESS_AUDIT.md) now requires an active site for a
-- new open assignment.
insert into public.sites (id, tenant_id, client_id, name, status) values
  ('00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000003001', 'Site A', 'active');

-- Org B structure (as service role, bypassing RLS, just to have cross-tenant targets)
reset role;
reset request.jwt.claims;
insert into public.departments (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000001002', '00000000-0000-0000-0000-0000000000b1', 'Operations B');
insert into public.positions (id, tenant_id, department_id, title) values
  ('00000000-0000-0000-0000-000000002002', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000001002', 'Cleaner B');
insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000003002', '00000000-0000-0000-0000-0000000000b1', 'Client B');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-000000004002', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000003002', 'Site B');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a2","app_metadata":{"role":"organization_administrator"}}';

-- Cross-tenant employee.department_id should be rejected
do $$
begin
  begin
    insert into public.employees (tenant_id, employee_number, first_name, last_name, department_id, employment_start_date)
    values ('00000000-0000-0000-0000-0000000000a1', 'E001', 'John', 'Doe', '00000000-0000-0000-0000-000000001002', current_date);
    raise exception 'SECURITY_FAILURE: cross-tenant employee.department_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant employee.department_id blocked (%)', sqlerrm;
  end;
end $$;

-- Cross-tenant employee.position_id should be rejected
do $$
begin
  begin
    insert into public.employees (tenant_id, employee_number, first_name, last_name, position_id, employment_start_date)
    values ('00000000-0000-0000-0000-0000000000a1', 'E002', 'Jane', 'Doe', '00000000-0000-0000-0000-000000002002', current_date);
    raise exception 'SECURITY_FAILURE: cross-tenant employee.position_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant employee.position_id blocked (%)', sqlerrm;
  end;
end $$;

-- Valid same-tenant employee succeeds
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, department_id, position_id, employment_start_date)
values ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000a1', 'E003', 'Real', 'Employee', '00000000-0000-0000-0000-000000001001', '00000000-0000-0000-0000-000000002001', current_date);

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employees where id = '00000000-0000-0000-0000-000000005001';
  if v_count != 1 then raise exception 'FAIL: valid same-tenant employee insert did not succeed'; end if;
  raise notice 'PASS: valid same-tenant employee insert succeeded';
end $$;

-- Cross-tenant site_assignment (Org A employee -> Org B site) should be rejected
do $$
begin
  begin
    insert into public.site_assignments (tenant_id, site_id, employee_id)
    values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004002', '00000000-0000-0000-0000-000000005001');
    raise exception 'SECURITY_FAILURE: cross-tenant site_assignment insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant site_assignment blocked (%)', sqlerrm;
  end;
end $$;

-- Valid same-tenant site assignment succeeds
insert into public.site_assignments (tenant_id, site_id, employee_id)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000004001', '00000000-0000-0000-0000-000000005001');

-- Team + team_members cross-tenant check
insert into public.teams (id, tenant_id, name, site_id) values
  ('00000000-0000-0000-0000-000000006001', '00000000-0000-0000-0000-0000000000a1', 'Team A', '00000000-0000-0000-0000-000000004001');

do $$
begin
  begin
    insert into public.team_members (team_id, employee_id, tenant_id) values
      ('00000000-0000-0000-0000-000000006001', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000b1');
    raise exception 'SECURITY_FAILURE: team_member with mismatched tenant_id succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: team_member tenant mismatch blocked (%)', sqlerrm;
  end;
end $$;

insert into public.team_members (team_id, employee_id, tenant_id) values
  ('00000000-0000-0000-0000-000000006001', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000000a1');

-- Audit coverage check
do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'employees' and entity_id = '00000000-0000-0000-0000-000000005001' and action = 'insert_employees';
  if v_count < 1 then raise exception 'FAIL: employee insert was not audit-logged'; end if;
  select count(*) into v_count from public.audit_log where entity_table = 'site_assignments' and action = 'insert_site_assignments';
  if v_count < 1 then raise exception 'FAIL: site_assignment insert was not audit-logged'; end if;
  select count(*) into v_count from public.audit_log where entity_table = 'teams' and action = 'insert_team_members';
  if v_count < 1 then raise exception 'FAIL: team_members insert was not audit-logged'; end if;
  raise notice 'PASS: employee/site_assignment/team_members inserts are all audit-logged';
end $$;

-- Operational role write access: a site_manager (not org admin) can create a team.
reset role;
reset request.jwt.claims;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a4', 'authenticated', 'authenticated', 'sitemgr-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"site_manager"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000a1', 'Site', 'Mgr', 'sitemgr-a@example.com', 'site_manager', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a4","app_metadata":{"role":"site_manager"}}';

insert into public.teams (tenant_id, name, site_id) values
  ('00000000-0000-0000-0000-0000000000a1', 'Team by Site Manager', '00000000-0000-0000-0000-000000004001');

do $$
declare v_count int;
begin
  select count(*) into v_count from public.teams where name = 'Team by Site Manager';
  if v_count != 1 then raise exception 'FAIL: site_manager could not create a team'; end if;
  raise notice 'PASS: site_manager (operational tier) can create a team';
end $$;

-- But a site_manager cannot create a department (org-structure tier only).
do $$
begin
  begin
    insert into public.departments (tenant_id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Should Fail Dept');
    raise exception 'SECURITY_FAILURE: site_manager created a department';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: site_manager blocked from creating a department (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;

rollback;
