-- Sebetsa — regression coverage for the P1 broader-audit finding (see
-- 20260920090300_p1_broader_blanket_select_narrowing.sql's own header for
-- full rationale and scope discipline): a blanket tenant-wide SELECT
-- policy on 12 tables let client_user (zero permissions) and other
-- under-privileged roles read real operational/business data gated by a
-- specific permission in rolePermissions.ts.
--
-- Confirmed by running this file against the pre-fix policies: every
-- SECURITY_FAILURE-labelled assertion below reproducibly succeeded (the
-- read leaked) before the fix, and is denied after it.
--
--   supabase start
--   cat supabase/rls-tests/p1_broader_blanket_select_narrowing.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-00000000fa01', 'Tenant A (broader SELECT narrowing)', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fa02', 'authenticated', 'authenticated', 'ops-fa@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"operations_manager"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fa03', 'authenticated', 'authenticated', 'admin-fa@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fa04', 'authenticated', 'authenticated', 'client-fa@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"client_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000fa05', 'authenticated', 'authenticated', 'emp-fa@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status) values
  ('00000000-0000-0000-0000-00000000fa02', '00000000-0000-0000-0000-00000000fa01', 'Ops', 'Manager', 'ops-fa@example.com', 'operations_manager', 'active'),
  ('00000000-0000-0000-0000-00000000fa03', '00000000-0000-0000-0000-00000000fa01', 'Admin', 'FA', 'admin-fa@example.com', 'organization_administrator', 'active'),
  ('00000000-0000-0000-0000-00000000fa04', '00000000-0000-0000-0000-00000000fa01', 'Client', 'User', 'client-fa@example.com', 'client_user', 'active'),
  ('00000000-0000-0000-0000-00000000fa05', '00000000-0000-0000-0000-00000000fa01', 'Employee', 'FA', 'emp-fa@example.com', 'employee', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fa03","app_metadata":{"role":"organization_administrator"}}';

insert into public.regions (id, tenant_id, name) values ('00000000-0000-0000-0000-00000000fa06', '00000000-0000-0000-0000-00000000fa01', 'Region FA');
insert into public.clients (id, tenant_id, region_id, name) values ('00000000-0000-0000-0000-00000000fa07', '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa06', 'Client FA');
insert into public.sites (id, tenant_id, client_id, name, status) values ('00000000-0000-0000-0000-00000000fa08', '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa07', 'Site FA', 'active');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status) values ('00000000-0000-0000-0000-00000000fa09', '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa07', 'CTR-FA-001', current_date, 'active');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_start_date) values ('00000000-0000-0000-0000-00000000fa0a', '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa05', 'FA001', 'Employee', 'FA', current_date - 30);
insert into public.assets (id, tenant_id, asset_number, name, category) values ('00000000-0000-0000-0000-00000000fa0b', '00000000-0000-0000-0000-00000000fa01', 'AST-FA-001', 'Asset FA', 'equipment');
insert into public.inventory_items (id, tenant_id, sku, name, category, unit) values ('00000000-0000-0000-0000-00000000fa0c', '00000000-0000-0000-0000-00000000fa01', 'SKU-FA-001', 'Item FA', 'consumables', 'each');
insert into public.compliance_requirements (id, tenant_id, name, category, applies_to_scope, recurrence_interval_days) values ('00000000-0000-0000-0000-00000000fa0d', '00000000-0000-0000-0000-00000000fa01', 'Requirement FA', 'safety', 'organization', 365);
insert into public.client_contacts (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-00000000fa0e', '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa07', 'Contact FA');
insert into public.sla_definitions (id, tenant_id, contract_id, name, metric_type, target_value, threshold_operator) values ('00000000-0000-0000-0000-00000000fa0f', '00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa09', 'SLA FA', 'staffing_fulfillment', 95, 'gte');
insert into public.employee_availability (tenant_id, employee_id, day_of_week, start_time, end_time) values ('00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-00000000fa0a', 1, '08:00', '17:00');

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- client_user (zero permissions) is denied on every narrowed table.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fa04","app_metadata":{"role":"client_user"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.assets where id = '00000000-0000-0000-0000-00000000fa0b';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read assets (asset.view not held)'; end if;
  raise notice 'PASS: client_user cannot read assets';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.inventory_items where id = '00000000-0000-0000-0000-00000000fa0c';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read inventory_items (inventory.view not held)'; end if;
  raise notice 'PASS: client_user cannot read inventory_items';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.compliance_requirements where id = '00000000-0000-0000-0000-00000000fa0d';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read compliance_requirements (compliance.view not held)'; end if;
  raise notice 'PASS: client_user cannot read compliance_requirements';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.client_contacts where id = '00000000-0000-0000-0000-00000000fa0e';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read client_contacts (org_structure.view not held)'; end if;
  raise notice 'PASS: client_user cannot read client_contacts';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.sla_definitions where id = '00000000-0000-0000-0000-00000000fa0f';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read sla_definitions (org_structure.view not held)'; end if;
  raise notice 'PASS: client_user cannot read sla_definitions';
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_availability where employee_id = '00000000-0000-0000-0000-00000000fa0a';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: client_user read employee_availability (availability.view not held)'; end if;
  raise notice 'PASS: client_user cannot read employee_availability';
end $$;

reset role;
reset request.jwt.claims;

-- ---------------------------------------------------------------------------
-- The authorized tier still reads every narrowed table (control — proves
-- this is a narrowing, not a lockout).

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fa02","app_metadata":{"role":"operations_manager"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.assets where id = '00000000-0000-0000-0000-00000000fa0b';
  if v_count <> 1 then raise exception 'FAIL: operations_manager could not read assets (control)'; end if;
  select count(*) into v_count from public.inventory_items where id = '00000000-0000-0000-0000-00000000fa0c';
  if v_count <> 1 then raise exception 'FAIL: operations_manager could not read inventory_items (control)'; end if;
  select count(*) into v_count from public.compliance_requirements where id = '00000000-0000-0000-0000-00000000fa0d';
  if v_count <> 1 then raise exception 'FAIL: operations_manager could not read compliance_requirements (control)'; end if;
  raise notice 'PASS: operations_manager (asset.view/inventory.view/compliance.view tier) still reads all three';
end $$;

reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fa03","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.client_contacts where id = '00000000-0000-0000-0000-00000000fa0e';
  if v_count <> 1 then raise exception 'FAIL: organization_administrator could not read client_contacts (control)'; end if;
  select count(*) into v_count from public.sla_definitions where id = '00000000-0000-0000-0000-00000000fa0f';
  if v_count <> 1 then raise exception 'FAIL: organization_administrator could not read sla_definitions (control)'; end if;
  raise notice 'PASS: organization_administrator (org_structure.view tier) still reads client_contacts/sla_definitions';
end $$;

reset role;
reset request.jwt.claims;

-- Employee: sees their own availability rows (self-service, unaffected by
-- the narrowing) but not another tenant's/role's availability data absent
-- the broad-view tier — this table's own-record branch is unchanged by
-- this fix, only the "any tenant member" branch was narrowed.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000fa05","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_availability where employee_id = '00000000-0000-0000-0000-00000000fa0a';
  if v_count <> 1 then raise exception 'FAIL: employee could not read their own availability (control)'; end if;
  raise notice 'PASS: employee still reads their own availability (can_view_scheduling_broad includes employee)';
end $$;

reset role;
reset request.jwt.claims;

rollback;
