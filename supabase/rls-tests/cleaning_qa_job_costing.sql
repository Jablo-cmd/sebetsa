-- Sebetsa Phase W/X — Cleaning QA / Inspections & Job Costing / Profitability:
-- RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/cleaning_qa_job_costing.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000791', 'Org Q1', 'active'),
  ('00000000-0000-0000-0000-000000000792', 'Org Q2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007901', 'authenticated', 'authenticated', 'admin-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007902', 'authenticated', 'authenticated', 'supervisor-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"supervisor"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007903', 'authenticated', 'authenticated', 'employee-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007904', 'authenticated', 'authenticated', 'client-q1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"client_user"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000007901', '00000000-0000-0000-0000-000000000791', 'Admin', 'Q1', 'admin-q1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000007902', '00000000-0000-0000-0000-000000000791', 'Supervisor', 'Q1', 'supervisor-q1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000007903', '00000000-0000-0000-0000-000000000791', 'Employee', 'Q1', 'employee-q1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000007904', '00000000-0000-0000-0000-000000000791', 'Client', 'Q1', 'client-q1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007901","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000007391', '00000000-0000-0000-0000-000000000791', 'Client Q1 Co');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-000000007491', '00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007391', 'Site Q1');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status, recurring_value, billing_frequency)
values ('00000000-0000-0000-0000-000000007591', '00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007391', 'CTR-Q-001', '2026-01-01', 'active', 10000, 'monthly');
insert into public.contract_sites (contract_id, site_id, tenant_id) values
  ('00000000-0000-0000-0000-000000007591', '00000000-0000-0000-0000-000000007491', '00000000-0000-0000-0000-000000000791');

insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name)
values ('00000000-0000-0000-0000-000000007801', '00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007903', 'EMP-Q-001', 'Employee', 'Q1');

-- Client A's portal link (fixture, superuser role — client_portal_users has
-- no direct INSERT policy, provision_client_portal_login() only).
reset role;
reset request.jwt.claims;
insert into public.client_portal_users (tenant_id, client_id, profile_id) values
  ('00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007391', '00000000-0000-0000-0000-000000007904');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007901","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- Inspection template + items.

insert into public.inspection_templates (id, tenant_id, name, pass_threshold)
values ('00000000-0000-0000-0000-000000007101', '00000000-0000-0000-0000-000000000791', 'Standard Office Clean', 80.00);
insert into public.inspection_template_items (id, tenant_id, template_id, area_label, criterion, max_score, weight, sort_order) values
  ('00000000-0000-0000-0000-000000007111', '00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007101', 'Reception', 'Floor cleanliness', 10, 2, 1),
  ('00000000-0000-0000-0000-000000007112', '00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007101', 'Restroom', 'Sanitation', 10, 1, 2);

insert into public.inspections (id, tenant_id, client_id, site_id, contract_id, template_id, status, scheduled_at)
values ('00000000-0000-0000-0000-000000007201', '00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007391', '00000000-0000-0000-0000-000000007491', '00000000-0000-0000-0000-000000007591', '00000000-0000-0000-0000-000000007101', 'scheduled', now());

-- ---------------------------------------------------------------------------
-- Cross-tenant / role isolation on templates and inspections before any
-- work happens.

reset role;
reset request.jwt.claims;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000007905', 'authenticated', 'authenticated', 'admin-q2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000007905', '00000000-0000-0000-0000-000000000792', 'Admin', 'Q2', 'admin-q2@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007905","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.inspections where tenant_id = '00000000-0000-0000-0000-000000000791';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: org Q2 admin sees % of org Q1''s inspections', v_count; end if;
  raise notice 'PASS: cross-tenant isolation holds for inspections';
end $$;

-- ---------------------------------------------------------------------------
-- A plain employee (worker) cannot operate the inspection at all.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007903","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.start_inspection('00000000-0000-0000-0000-000000007201');
    raise exception 'SECURITY_FAILURE: a plain employee started an inspection';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a plain employee (worker) cannot start an inspection (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- A supervisor (can_manage_operations, but not can_manage_org_structure)
-- can run the inspection lifecycle end to end.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007902","app_metadata":{"role":"supervisor"}}';

do $$
declare v_result public.inspections;
begin
  select * into v_result from public.start_inspection('00000000-0000-0000-0000-000000007201');
  if v_result.status <> 'in_progress' or v_result.inspector_id <> '00000000-0000-0000-0000-000000007902' then
    raise exception 'FAIL: expected in_progress with inspector_id set to the supervisor, got status=%, inspector_id=%', v_result.status, v_result.inspector_id;
  end if;
  raise notice 'PASS: a supervisor can start the inspection; inspector_id is server-derived';
end $$;

do $$
begin
  perform public.submit_inspection_result('00000000-0000-0000-0000-000000007201', '00000000-0000-0000-0000-000000007111', 8);
  begin
    perform public.complete_inspection('00000000-0000-0000-0000-000000007201');
    raise exception 'SECURITY_FAILURE: an inspection was completed with a missing criterion result';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: complete_inspection refuses to finish while a criterion has no submitted result (%)', sqlerrm;
  end;
end $$;

do $$
declare v_result public.inspections;
begin
  perform public.submit_inspection_result('00000000-0000-0000-0000-000000007201', '00000000-0000-0000-0000-000000007112', 10);
  select * into v_result from public.complete_inspection('00000000-0000-0000-0000-000000007201');
  if v_result.status <> 'completed' or v_result.overall_score <> 86.67 or v_result.passed <> true then
    raise exception 'FAIL: expected completed, overall_score=86.67, passed=true — got status=%, score=%, passed=%', v_result.status, v_result.overall_score, v_result.passed;
  end if;
  raise notice 'PASS: complete_inspection computes the deterministic weighted score (8*2+10*1)/(10*2+10*1)*100 = 86.67 server-side, and passed=true (>= 80 threshold)';
end $$;

-- ---------------------------------------------------------------------------
-- Defect lifecycle, close-with-open-defects guard, self-verification guard.

do $$
declare v_defect public.defects;
begin
  select * into v_defect from public.create_defect('00000000-0000-0000-0000-000000007201', 'Restroom floor not sanitised', 'high', 'Restroom', p_inspection_result_id => null);
  if v_defect.status <> 'open' then raise exception 'FAIL: expected a new defect to be open, got %', v_defect.status; end if;

  begin
    perform public.close_inspection('00000000-0000-0000-0000-000000007201');
    raise exception 'SECURITY_FAILURE: an inspection was closed while a defect was still open';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: close_inspection refuses to close while an open defect remains (%)', sqlerrm;
  end;
end $$;

do $$
declare v_defect_id uuid; v_result public.defects;
begin
  select id into v_defect_id from public.defects where inspection_id = '00000000-0000-0000-0000-000000007201';
  select * into v_result from public.resolve_defect(v_defect_id, 'Re-cleaned the restroom floor', 'Retrained the site team');
  if v_result.status <> 'resolved' or v_result.resolved_by <> '00000000-0000-0000-0000-000000007902' then
    raise exception 'FAIL: expected resolved with resolved_by the calling supervisor, got status=%, resolved_by=%', v_result.status, v_result.resolved_by;
  end if;

  begin
    perform public.verify_defect(v_defect_id);
    raise exception 'SECURITY_FAILURE: the same supervisor verified a defect they resolved themselves';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: self-verification is blocked — the resolver cannot also verify their own defect (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_defect_id uuid; v_result public.defects;
begin
  select id into v_defect_id from public.defects where inspection_id = '00000000-0000-0000-0000-000000007201';
  select * into v_result from public.verify_defect(v_defect_id);
  if v_result.status <> 'verified' then raise exception 'FAIL: expected verified, got %', v_result.status; end if;
  raise notice 'PASS: a different manager can verify a defect resolved by someone else';
end $$;

do $$
declare v_result public.inspections;
begin
  select * into v_result from public.close_inspection('00000000-0000-0000-0000-000000007201');
  if v_result.status <> 'closed' then raise exception 'FAIL: expected closed, got %', v_result.status; end if;
  raise notice 'PASS: once all defects are resolved/verified, close_inspection succeeds';
end $$;

do $$
declare v_defect_id uuid; v_reinspection public.inspections; v_original public.inspections;
begin
  select id into v_defect_id from public.defects where inspection_id = '00000000-0000-0000-0000-000000007201';
  select * into v_reinspection from public.schedule_reinspection(v_defect_id, '2026-09-25 09:00:00+02');
  select * into v_original from public.inspections where id = '00000000-0000-0000-0000-000000007201';
  if v_reinspection.reinspection_of <> v_original.id or v_reinspection.site_id <> v_original.site_id or v_reinspection.client_id <> v_original.client_id then
    raise exception 'FAIL: reinspection not correctly linked/copied from the original';
  end if;
  if not exists (select 1 from public.defects where id = v_defect_id and reinspection_id = v_reinspection.id) then
    raise exception 'FAIL: defect.reinspection_id was not linked to the new inspection';
  end if;
  raise notice 'PASS: schedule_reinspection creates a real linked inspection, copying client/site/template from the original';
end $$;

-- ---------------------------------------------------------------------------
-- Client visibility: the client can see their own completed inspection and
-- its defect, but cannot operate the inspection lifecycle themselves.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007904","app_metadata":{"role":"client_user"}}';

do $$
declare v_inspection_count int; v_defect_count int;
begin
  select count(*) into v_inspection_count from public.inspections where id = '00000000-0000-0000-0000-000000007201';
  select count(*) into v_defect_count from public.defects where inspection_id = '00000000-0000-0000-0000-000000007201';
  if v_inspection_count <> 1 or v_defect_count <> 1 then
    raise exception 'FAIL: client should see their own completed inspection and its defect, got inspection_count=%, defect_count=%', v_inspection_count, v_defect_count;
  end if;
  raise notice 'PASS: a client can see their own inspection and its defect (relevant QA visibility)';
end $$;

do $$
begin
  begin
    perform public.close_inspection('00000000-0000-0000-0000-000000007201');
    raise exception 'SECURITY_FAILURE: a client operated close_inspection directly';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a client cannot directly operate the inspection lifecycle (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Job costing: real cost configuration (employee_cost_rates,
-- inventory_items.standard_unit_cost, cost_entries), restricted to the
-- org-structure tier — not visible to a supervisor who can merely run
-- operations.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007901","app_metadata":{"role":"organization_administrator"}}';

insert into public.employee_cost_rates (tenant_id, employee_id, hourly_rate, effective_from)
values ('00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007801', 100, '2026-01-01');

insert into public.attendance_records (tenant_id, site_id, employee_id, status, clock_in_at, clock_out_at)
values ('00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007491', '00000000-0000-0000-0000-000000007801', 'present', '2026-09-05 08:00:00+02', '2026-09-05 16:00:00+02');

insert into public.inventory_items (id, tenant_id, sku, name, category, standard_unit_cost)
values ('00000000-0000-0000-0000-000000007601', '00000000-0000-0000-0000-000000000791', 'SKU-Q-001', 'Floor cleaner', 'chemicals', 50);

do $$
begin
  perform public.record_inventory_movement('00000000-0000-0000-0000-000000007601', '00000000-0000-0000-0000-000000007491', 'issue', 3, 'consumed on Site Q1', true);
end $$;

insert into public.cost_entries (tenant_id, contract_id, site_id, category, description, amount, cost_date) values
  ('00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007591', '00000000-0000-0000-0000-000000007491', 'equipment', 'Floor buffer rental', 200, '2026-09-10'),
  ('00000000-0000-0000-0000-000000000791', '00000000-0000-0000-0000-000000007591', '00000000-0000-0000-0000-000000007491', 'other', 'Waste disposal', 75, '2026-09-12');

do $$
declare v_invoice public.invoices;
begin
  select * into v_invoice from public.generate_contract_billing_invoice('00000000-0000-0000-0000-000000007591', '2026-09-01', '2026-09-30');
  perform public.issue_invoice(v_invoice.id, '2026-09-15', '2026-10-15');
end $$;

do $$
declare v_result record;
begin
  select * into v_result from public.get_contract_profitability('00000000-0000-0000-0000-000000007591', '2026-09-01', '2026-09-30');
  if v_result.revenue <> 11500 or v_result.labour_cost <> 800 or v_result.consumables_cost <> 150
     or v_result.equipment_cost <> 200 or v_result.other_cost <> 75 or v_result.gross_contribution <> 10275
     or v_result.gross_margin_pct <> 89.35 then
    raise exception 'FAIL: unexpected profitability figures: revenue=%, labour=%, consumables=%, equipment=%, other=%, contribution=%, margin_pct=%',
      v_result.revenue, v_result.labour_cost, v_result.consumables_cost, v_result.equipment_cost, v_result.other_cost, v_result.gross_contribution, v_result.gross_margin_pct;
  end if;
  raise notice 'PASS: get_contract_profitability computes revenue(11500) - labour(800) - consumables(150) - equipment(200) - other(75) = gross_contribution(10275), margin_pct=89.35%%, all from real persisted aggregates';
end $$;

do $$
declare v_result record;
begin
  select * into v_result from public.get_contract_profitability('00000000-0000-0000-0000-000000007591', '2026-10-01', '2026-10-31');
  if v_result.revenue <> 0 or v_result.gross_margin_pct is not null then
    raise exception 'FAIL: expected zero revenue and a null (not zero) margin_pct for a period with no invoices, got revenue=%, margin_pct=%', v_result.revenue, v_result.gross_margin_pct;
  end if;
  raise notice 'PASS: get_contract_profitability returns margin_pct=null (never a misleading zero) when revenue is zero for the period';
end $$;

-- ---------------------------------------------------------------------------
-- A supervisor (operations tier, not org-structure tier) cannot see cost
-- configuration or profitability — commercially sensitive.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007902","app_metadata":{"role":"supervisor"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.employee_cost_rates;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: a supervisor sees % employee_cost_rates rows', v_count; end if;
  raise notice 'PASS: a supervisor (operations tier) cannot see employee_cost_rates (org-structure tier only)';
end $$;

do $$
begin
  begin
    perform public.get_contract_profitability('00000000-0000-0000-0000-000000007591', '2026-09-01', '2026-09-30');
    raise exception 'SECURITY_FAILURE: a supervisor accessed contract profitability';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a supervisor cannot access contract profitability (org-structure tier only) (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Final cross-tenant isolation on job-costing tables.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000007905","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_rates int; v_costs int;
begin
  select count(*) into v_rates from public.employee_cost_rates where tenant_id = '00000000-0000-0000-0000-000000000791';
  select count(*) into v_costs from public.cost_entries where tenant_id = '00000000-0000-0000-0000-000000000791';
  if v_rates <> 0 or v_costs <> 0 then
    raise exception 'SECURITY_FAILURE: org Q2 admin sees %/% of org Q1''s employee_cost_rates/cost_entries', v_rates, v_costs;
  end if;
  raise notice 'PASS: cross-tenant isolation holds for employee_cost_rates/cost_entries';
end $$;

rollback;
