-- Sebetsa Phase J — Workforce & Site Operations: RLS checks for
-- site_staffing_requirements (the one new table this phase introduces —
-- everything else is an aggregation layer over already-tested tables).
--
--   supabase start
--   cat supabase/rls-tests/workforce_site_operations.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000091', 'Org G', 'active'),
  ('00000000-0000-0000-0000-000000000081', 'Org H', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000092', 'authenticated', 'authenticated', 'admin-g@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000093', 'authenticated', 'authenticated', 'employee-g1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-000000000092', '00000000-0000-0000-0000-000000000091', 'Admin', 'G', 'admin-g@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-000000000093', '00000000-0000-0000-0000-000000000091', 'Emp', 'One', 'employee-g1@example.com', 'employee', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000092","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003301', '00000000-0000-0000-0000-000000000091', 'Client G');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004301', '00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000003301', 'Site G');

insert into public.site_staffing_requirements (tenant_id, site_id, label, required_count)
values ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000004301', 'Day shift guards', 4);

reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003302', '00000000-0000-0000-0000-000000000081', 'Client H');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004302', '00000000-0000-0000-0000-000000000081', '00000000-0000-0000-0000-000000003302', 'Site H');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000092","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    insert into public.site_staffing_requirements (tenant_id, site_id, label, required_count)
    values ('00000000-0000-0000-0000-000000000091', '00000000-0000-0000-0000-000000004302', 'Cross-tenant', 1);
    raise exception 'SECURITY_FAILURE: cross-tenant site_staffing_requirement.site_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant site_staffing_requirement.site_id blocked (%)', sqlerrm;
  end;
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'site_staffing_requirements' and action = 'insert_site_staffing_requirements';
  if v_count < 1 then raise exception 'FAIL: site_staffing_requirement insert was not audit-logged'; end if;
  raise notice 'PASS: site_staffing_requirement insert is audit-logged';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000093","app_metadata":{"role":"employee"}}';

do $$
declare v_rows_affected int;
begin
  update public.site_staffing_requirements set required_count = 99 where tenant_id = '00000000-0000-0000-0000-000000000091';
  get diagnostics v_rows_affected = row_count;
  if v_rows_affected <> 0 then raise exception 'SECURITY_FAILURE: employee updated site_staffing_requirements (% rows)', v_rows_affected; end if;
  raise notice 'PASS: employee update of site_staffing_requirements affects 0 rows (RLS hides it)';
end $$;

-- Corrected 2026-09-19 as part of the production-readiness audit's C-2
-- remediation (docs/PRODUCTION_READINESS_AUDIT.md): site_staffing_requirements
-- maps to the site_assignment.view permission in rolePermissions.ts, which
-- employee does not hold. The previous assertion (employee sees it via
-- "broad SELECT") only held because the old policy had no role check.
do $$
declare v_count int;
begin
  select count(*) into v_count from public.site_staffing_requirements where tenant_id = '00000000-0000-0000-0000-000000000091';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: employee (no site_assignment.view) read site_staffing_requirements, got % rows', v_count; end if;
  raise notice 'PASS: employee (no site_assignment.view) correctly sees zero staffing requirements';
end $$;

reset role;
reset request.jwt.claims;

rollback;
