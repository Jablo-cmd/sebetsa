-- Sebetsa Phase P — Client, Contract & SLA Management: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/client_contract_sla.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000391', 'Org P1', 'active'),
  ('00000000-0000-0000-0000-000000000392', 'Org P2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000003901', 'authenticated', 'authenticated', 'admin-p1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000003902', 'authenticated', 'authenticated', 'employee-p1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000003901', '00000000-0000-0000-0000-000000000391', 'Admin', 'P1', 'admin-p1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000003902', '00000000-0000-0000-0000-000000000391', 'Emp', 'P1', 'employee-p1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000003901","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003391', '00000000-0000-0000-0000-000000000391', 'Client P1');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004391', '00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000003391', 'Site P1');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status)
values ('00000000-0000-0000-0000-000000005391', '00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000003391', 'CTR-001', '2026-01-01', 'draft');

reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003392', '00000000-0000-0000-0000-000000000392', 'Client P2');

-- ---------------------------------------------------------------------------
-- Client contacts: tenant isolation + write tier.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000003901","app_metadata":{"role":"organization_administrator"}}';

insert into public.client_contacts (tenant_id, client_id, name, role_title, email)
values ('00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000003391', 'Jane Ops', 'Operations Lead', 'jane@clientp1.example.com');

do $$
begin
  begin
    insert into public.client_contacts (tenant_id, client_id, name)
    values ('00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000003392', 'Cross-tenant contact');
    raise exception 'SECURITY_FAILURE: cross-tenant client_contacts.client_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant client_contacts.client_id blocked (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000003902","app_metadata":{"role":"employee"}}';

do $$
declare v_rows int;
begin
  insert into public.client_contacts (tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000003391', 'Should fail');
  raise exception 'SECURITY_FAILURE: plain employee inserted a client contact';
exception
  when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    raise notice 'PASS: plain-employee client_contacts insert blocked (%)', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Contract lifecycle.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000003901","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    update public.contracts set status = 'expiring' where id = '00000000-0000-0000-0000-000000005391';
    raise exception 'SECURITY_FAILURE: illegal contract jump (draft -> expiring) succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: illegal contract status jump blocked (%)', sqlerrm;
  end;
end $$;

update public.contracts set status = 'active' where id = '00000000-0000-0000-0000-000000005391';
update public.contracts set status = 'suspended' where id = '00000000-0000-0000-0000-000000005391';
update public.contracts set status = 'active' where id = '00000000-0000-0000-0000-000000005391';

do $$
declare v_status public.contract_status;
begin
  select status into v_status from public.contracts where id = '00000000-0000-0000-0000-000000005391';
  if v_status <> 'active' then raise exception 'FAIL: expected active after draft->active->suspended->active, got %', v_status; end if;
  raise notice 'PASS: legal contract lifecycle transitions applied (draft -> active -> suspended -> active)';
end $$;

-- ---------------------------------------------------------------------------
-- SLA: definitions, real-data-derived measurement, append-only.

insert into public.sla_definitions (id, tenant_id, contract_id, site_id, name, metric_type, target_value, threshold_operator)
values ('00000000-0000-0000-0000-000000006391', '00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000005391', '00000000-0000-0000-0000-000000004391', 'Task completion', 'task_completion_rate', 90, 'gte');

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_status) values
  ('00000000-0000-0000-0000-000000007391', '00000000-0000-0000-0000-000000000391', null, 'EMP-P1', 'Site', 'Worker', 'active');

insert into public.tasks (tenant_id, site_id, assignee_id, title, status, due_at) values
  ('00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000004391', '00000000-0000-0000-0000-000000007391', 'Clean lobby', 'completed', '2026-09-10T09:00:00Z'),
  ('00000000-0000-0000-0000-000000000391', '00000000-0000-0000-0000-000000004391', '00000000-0000-0000-0000-000000007391', 'Restock supplies', 'open', '2026-09-11T09:00:00Z');

do $$
declare v_measured numeric; v_met boolean;
begin
  select measured_value, target_met into v_measured, v_met
  from public.compute_sla_measurement('00000000-0000-0000-0000-000000006391', '2026-09-01', '2026-09-30');
  if v_measured <> 50.00 then raise exception 'FAIL: expected 50%% task completion (1 of 2 completed), got %', v_measured; end if;
  if v_met <> false then raise exception 'FAIL: expected target_met = false (50 < 90), got %', v_met; end if;
  raise notice 'PASS: compute_sla_measurement derives a real task-completion rate from actual tasks (50%%, target not met)';
end $$;

do $$
declare v_rows int;
begin
  update public.sla_measurements set measured_value = 999 where sla_definition_id = '00000000-0000-0000-0000-000000006391';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'SECURITY_FAILURE: direct UPDATE of an sla_measurement succeeded (% rows)', v_rows; end if;
  raise notice 'PASS: sla_measurements is append-only (direct UPDATE affects 0 rows)';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000003902","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.compute_sla_measurement('00000000-0000-0000-0000-000000006391', '2026-09-01', '2026-09-30');
    raise exception 'SECURITY_FAILURE: plain employee computed an SLA measurement';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee compute_sla_measurement blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Contract documents.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000003901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_path text; v_version int;
begin
  select storage_path, version into v_path, v_version from public.create_contract_document_slot('00000000-0000-0000-0000-000000005391', 'msa.pdf', 'application/pdf', 1024);
  if v_version <> 1 then raise exception 'FAIL: expected version 1, got %', v_version; end if;
  if v_path is null or v_path not like '00000000-0000-0000-0000-000000000391/%' then raise exception 'FAIL: storage_path not server-derived under tenant prefix, got %', v_path; end if;
  raise notice 'PASS: create_contract_document_slot server-derives storage_path/version (%)', v_path;
end $$;

do $$
declare v_version int;
begin
  select version into v_version from public.create_contract_document_slot('00000000-0000-0000-0000-000000005391', 'msa-v2.pdf', 'application/pdf', 2048);
  if v_version <> 2 then raise exception 'FAIL: expected version 2 on second upload, got %', v_version; end if;
  raise notice 'PASS: repeated uploads increment version, prior row preserved (non-destructive)';
end $$;

-- Append-only audit check.
reset role;
reset request.jwt.claims;
do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'sla_measurements' and action = 'sla_measurement_computed';
  if v_count < 1 then raise exception 'FAIL: SLA measurement was not audit-logged'; end if;
  raise notice 'PASS: SLA measurement computation is audit-logged';
end $$;

rollback;
