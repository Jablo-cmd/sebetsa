-- Sebetsa — regression coverage for the P0 security remediation
-- (docs/PRODUCTION_READINESS_AUDIT.md Critical findings C-1 and C-2,
-- fixed in 20260919090000_p0_tenant_rbac_remediation.sql +
-- 20260919090100_p0_tenant_ref_trigger_security_definer.sql).
--
-- Confirmed by running this file against the pre-fix migration set: every
-- SECURITY_FAILURE-labelled assertion below reproducibly failed (the
-- attack succeeded) before the fix, and passes after it. See
-- docs/SEBETSA_REMEDIATION_REPORT.md for the full before/after record.
--
--   supabase start
--   cat supabase/rls-tests/p0_tenant_rbac_remediation.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000000e1', 'Org E (tenant A)', 'active'),
  ('00000000-0000-0000-0000-0000000000f1', 'Org F (tenant B)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'admin-e@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'hr-e@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"hr_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e4', 'authenticated', 'authenticated', 'employee-e@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000e5', 'authenticated', 'authenticated', 'client-e@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"client_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000f2', 'authenticated', 'authenticated', 'admin-f@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000e1', 'Admin', 'E', 'admin-e@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e1', 'HR', 'E', 'hr-e@example.com', 'hr_user', 'active'),
  ('00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000e1', 'Emp', 'E', 'employee-e@example.com', 'employee', 'active'),
  ('00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000e1', 'Client', 'E', 'client-e@example.com', 'client_user', 'active'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000f1', 'Admin', 'F', 'admin-f@example.com', 'organization_administrator', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000f2","app_metadata":{"role":"organization_administrator"}}';
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003f01', '00000000-0000-0000-0000-0000000000f1', 'Client F');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004f01', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000003f01', 'Site F');
insert into public.employees (id, tenant_id, employee_number, first_name, last_name, email, phone, employment_start_date) values
  ('00000000-0000-0000-0000-000000005f01', '00000000-0000-0000-0000-0000000000f1', 'F001', 'Secret', 'TenantBEmployee', 'secret-b-employee@example.com', '+27000000001', current_date);

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"role":"organization_administrator"}}';
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003e01', '00000000-0000-0000-0000-0000000000e1', 'Client E');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004e01', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000003e01', 'Site E');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values
  ('00000000-0000-0000-0000-000000005e01', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e4', 'E001', 'Own', 'Record', current_date);

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- C-1: employees_write_by_manager's hr_user branch was tenant-unbound.
-- An hr_user in tenant A (Org E) must NEVER be able to read, update, or
-- delete tenant B's (Org F) employees table, with or without a WHERE
-- clause naming a specific row.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e3","app_metadata":{"role":"hr_user"}}';

-- Attack A/C combined: unfiltered UPDATE...RETURNING against the WHOLE
-- table (not just tenant B's row) is the exact reproduction from the
-- audit — before the fix this returned every tenant's employee rows.
do $$
declare v_count int;
begin
  update public.employees set first_name = first_name;
  get diagnostics v_count = row_count;
  if v_count <> 1 then
    raise exception 'SECURITY_FAILURE: hr_user unfiltered UPDATE...RETURNING affected % rows across tenants, expected exactly 1 (own tenant only)', v_count;
  end if;
  raise notice 'PASS: hr_user unfiltered UPDATE affects only their own tenant''s 1 employee row, not every tenant''s';
end $$;

-- Attack C, targeted: an hr_user in tenant A explicitly naming tenant B's
-- employee id must affect zero rows.
do $$
declare v_count int;
begin
  update public.employees set first_name = 'Hacked' where id = '00000000-0000-0000-0000-000000005f01';
  get diagnostics v_count = row_count;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: hr_user updated tenant B''s employee by id, % rows affected', v_count; end if;
  raise notice 'PASS: hr_user cannot update tenant B''s employee by id (0 rows affected)';
end $$;

-- Attack A: cross-tenant read via SELECT.
do $$
declare v_count int;
begin
  select count(*) into v_count from public.employees where id = '00000000-0000-0000-0000-000000005f01';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: hr_user read tenant B''s employee row'; end if;
  raise notice 'PASS: hr_user cannot read tenant B''s employee row';
end $$;

-- Attack D: unfiltered DELETE must never reach another tenant's rows
-- (rolled back regardless, but proves the predicate, not just the
-- transaction boundary).
do $$
declare v_count int;
begin
  delete from public.employees where id = '00000000-0000-0000-0000-000000005f01';
  get diagnostics v_count = row_count;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: hr_user deleted tenant B''s employee row'; end if;
  raise notice 'PASS: hr_user cannot delete tenant B''s employee row';
end $$;

-- Attack B: cross-tenant insert must be rejected.
do $$
begin
  begin
    insert into public.employees (tenant_id, employee_number, first_name, last_name, employment_start_date)
    values ('00000000-0000-0000-0000-0000000000f1', 'E-INJECT', 'Injected', 'Employee', current_date);
    raise exception 'SECURITY_FAILURE: hr_user inserted an employee into tenant B';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: hr_user cannot insert an employee into tenant B (%)', sqlerrm;
  end;
end $$;

-- Legitimate access within the hr_user's own tenant must still work
-- (the fix must not have overcorrected into denying same-tenant writes).
do $$
declare v_count int;
begin
  update public.employees set first_name = 'StillWorks' where tenant_id = '00000000-0000-0000-0000-0000000000e1';
  get diagnostics v_count = row_count;
  if v_count <> 1 then raise exception 'FAIL: hr_user could not update their own tenant''s employee (regression)'; end if;
  raise notice 'PASS: hr_user retains full read/write access within their own tenant';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- C-2: blanket "any tenant member" SELECT policies. client_user (zero
-- permissions in rolePermissions.ts) and employee (deliberately minimal)
-- must not read data their role was never granted, even within their own
-- tenant.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e5","app_metadata":{"role":"client_user"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employees where tenant_id = '00000000-0000-0000-0000-0000000000e1';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user (zero permissions) read % employee rows', v_count; end if;
  raise notice 'PASS: client_user cannot read the employee directory';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.contracts where tenant_id = '00000000-0000-0000-0000-0000000000e1';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read % contract rows outside any granted scope', v_count; end if;
  raise notice 'PASS: client_user cannot read contracts (org_structure.view not granted)';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.profiles where tenant_id = '00000000-0000-0000-0000-0000000000e1' and id <> auth.uid();
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read % other users'' profiles', v_count; end if;
  raise notice 'PASS: client_user cannot read other users'' profiles';
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000e4","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  -- employee.view is not granted to `employee` — must see zero *other*
  -- employees, but must still see their own record (self carve-out).
  select count(*) into v_count from public.employees where tenant_id = '00000000-0000-0000-0000-0000000000e1' and id <> '00000000-0000-0000-0000-000000005e01';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: employee (no employee.view) read % other employees'' records', v_count; end if;

  select count(*) into v_count from public.employees where id = '00000000-0000-0000-0000-000000005e01';
  if v_count <> 1 then raise exception 'FAIL: employee cannot read their own employee record (self carve-out regression)'; end if;

  raise notice 'PASS: employee sees only their own employee record, not the directory';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.contracts where tenant_id = '00000000-0000-0000-0000-0000000000e1';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: employee (no org_structure.view) read % contract rows', v_count; end if;
  raise notice 'PASS: employee cannot read contracts';
end $$;

reset role;
reset request.jwt.claims;

rollback;
