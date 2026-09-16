-- Sebetsa Phase U/V — Variation Orders & Billing/Invoicing: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/variation_orders_billing.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000691', 'Org V1', 'active'),
  ('00000000-0000-0000-0000-000000000692', 'Org V2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006901', 'authenticated', 'authenticated', 'admin-v1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006902', 'authenticated', 'authenticated', 'employee-v1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006903', 'authenticated', 'authenticated', 'client-a@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"client_user"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006904', 'authenticated', 'authenticated', 'client-b@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"client_user"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000006901', '00000000-0000-0000-0000-000000000691', 'Admin', 'V1', 'admin-v1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000006902', '00000000-0000-0000-0000-000000000691', 'Emp', 'V1', 'employee-v1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000006903', '00000000-0000-0000-0000-000000000691', 'Client', 'A', 'client-a@example.com', 'active'),
  ('00000000-0000-0000-0000-000000006904', '00000000-0000-0000-0000-000000000691', 'Client', 'B', 'client-b@example.com', 'active');

insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-000000006391', '00000000-0000-0000-0000-000000000691', 'Client A Co'),
  ('00000000-0000-0000-0000-000000006392', '00000000-0000-0000-0000-000000000691', 'Client B Co');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-000000006491', '00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006391', 'Site A1'),
  ('00000000-0000-0000-0000-000000006492', '00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006392', 'Site B1');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status, recurring_value, billing_frequency)
values ('00000000-0000-0000-0000-000000006591', '00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006391', 'CTR-V-001', '2026-01-01', 'active', 15000, 'monthly');
insert into public.contract_sites (contract_id, site_id, tenant_id) values
  ('00000000-0000-0000-0000-000000006591', '00000000-0000-0000-0000-000000006491', '00000000-0000-0000-0000-000000000691');

-- Link client_portal_users for Client A and Client B. This table has no
-- direct INSERT policy at all (only provision_client_portal_login(), a
-- SECURITY DEFINER RPC, may create rows) — inserted here as the
-- superuser fixture role (clients must exist first for the tenant-ref
-- trigger), before switching to `authenticated` below.
insert into public.client_portal_users (tenant_id, client_id, profile_id) values
  ('00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006391', '00000000-0000-0000-0000-000000006903'),
  ('00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006392', '00000000-0000-0000-0000-000000006904');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006901","app_metadata":{"role":"organization_administrator"}}';

-- ---------------------------------------------------------------------------
-- current_client_id() isolation.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006903","app_metadata":{"role":"client_user"}}';

do $$
declare v_client_id uuid;
begin
  select public.current_client_id() into v_client_id;
  if v_client_id <> '00000000-0000-0000-0000-000000006391' then raise exception 'FAIL: expected current_client_id() to return Client A''s id, got %', v_client_id; end if;
  raise notice 'PASS: current_client_id() correctly resolves Client A''s own portal user to Client A';
end $$;

-- ---------------------------------------------------------------------------
-- submit_service_request: server-derived client_id, ownership validated.

do $$
begin
  begin
    perform public.submit_service_request('additional_cleaning', 'Extra clean needed', p_site_id => '00000000-0000-0000-0000-000000006492');
    raise exception 'SECURITY_FAILURE: Client A submitted a request against Client B''s site';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: Client A cannot submit a service request against Client B''s site (%)', sqlerrm;
  end;
end $$;

do $$
declare v_request public.service_requests;
begin
  select * into v_request from public.submit_service_request('additional_cleaning', 'Deep clean reception', p_site_id => '00000000-0000-0000-0000-000000006491', p_contract_id => '00000000-0000-0000-0000-000000006591');
  if v_request.client_id <> '00000000-0000-0000-0000-000000006391' then raise exception 'FAIL: request client_id not server-derived correctly'; end if;
  if v_request.origin <> 'client' then raise exception 'FAIL: expected origin=client'; end if;
  raise notice 'PASS: Client A can submit a legitimate service request against their own site; client_id/origin are server-derived';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006904","app_metadata":{"role":"client_user"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.service_requests where client_id = '00000000-0000-0000-0000-000000006391';
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: Client B sees % of Client A''s service requests', v_count; end if;
  raise notice 'PASS: Client B cannot see Client A''s service requests (client-level isolation within the same tenant)';
end $$;

-- ---------------------------------------------------------------------------
-- assess_service_request -> variation_orders, quote linkage, client decision.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_request_id uuid; v_variation public.variation_orders;
begin
  select id into v_request_id from public.service_requests where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  select * into v_variation from public.assess_service_request(v_request_id, 'Deep clean reception area', 'Client requested deep clean', 'Carpet stains');
  if v_variation.status <> 'assessed' then raise exception 'FAIL: expected variation status assessed, got %', v_variation.status; end if;

  insert into public.quotes (id, tenant_id, client_id, quote_number, tax_rate)
  values ('00000000-0000-0000-0000-000000006691', '00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006391', 'QT-V-001', 15);
  insert into public.quote_line_items (tenant_id, quote_id, description, quantity, unit_rate)
  values ('00000000-0000-0000-0000-000000000691', '00000000-0000-0000-0000-000000006691', 'Deep clean labour', 10, 200);
  perform public.recompute_quote_totals('00000000-0000-0000-0000-000000006691');

  perform public.link_variation_quote(v_variation.id, '00000000-0000-0000-0000-000000006691');
  perform public.mark_variation_quoted(v_variation.id);
  update public.quotes set status = 'sent' where id = '00000000-0000-0000-0000-000000006691';
  update public.quotes set status = 'viewed' where id = '00000000-0000-0000-0000-000000006691';

  raise notice 'PASS: assess_service_request -> link_variation_quote -> mark_variation_quoted reuses the existing quote engine end to end';
end $$;

do $$
begin
  begin
    update public.quotes set total_amount = 1 where id = '00000000-0000-0000-0000-000000006691';
    raise exception 'SECURITY_FAILURE: quotes.total_amount was directly writable';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: quotes.total_amount cannot be directly forged even by an authorized manager (column-level protection) (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006904","app_metadata":{"role":"client_user"}}';

do $$
declare v_variation_id uuid;
begin
  select id into v_variation_id from public.variation_orders where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  begin
    perform public.client_decide_variation(v_variation_id, true);
    raise exception 'SECURITY_FAILURE: Client B approved Client A''s variation';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: Client B cannot approve Client A''s variation (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006903","app_metadata":{"role":"client_user"}}';

do $$
declare v_variation_id uuid; v_result public.variation_orders;
begin
  select id into v_variation_id from public.variation_orders where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  select * into v_result from public.client_decide_variation(v_variation_id, true);
  if v_result.status <> 'approved' then raise exception 'FAIL: expected variation approved, got %', v_result.status; end if;
  raise notice 'PASS: Client A (the real owner) can approve their own variation';
end $$;

do $$
declare v_variation_id uuid;
begin
  select id into v_variation_id from public.variation_orders where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  begin
    perform public.client_decide_variation(v_variation_id, true);
    raise exception 'SECURITY_FAILURE: an already-approved variation was decided a second time';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an already-decided variation cannot be decided again (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- schedule_variation_work / completion guard / invoicing.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_variation_id uuid; v_result public.variation_orders;
begin
  select id into v_variation_id from public.variation_orders where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  select * into v_result from public.schedule_variation_work(v_variation_id);
  if v_result.status <> 'scheduled' or v_result.task_id is null then raise exception 'FAIL: expected scheduled with a real task_id, got status=%, task_id=%', v_result.status, v_result.task_id; end if;

  perform public.transition_variation_status(v_variation_id, 'in_progress');

  begin
    perform public.transition_variation_status(v_variation_id, 'completed');
    raise exception 'SECURITY_FAILURE: variation marked completed while its linked task is still open';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a variation cannot be marked completed while its linked task is not actually done (%)', sqlerrm;
  end;

  update public.tasks set status = 'in_progress' where id = v_result.task_id;
  update public.tasks set status = 'completed', completed_by = auth.uid(), completed_at = now() where id = v_result.task_id;
  perform public.transition_variation_status(v_variation_id, 'completed');

  raise notice 'PASS: once the linked task is genuinely completed, the variation can be marked completed';
end $$;

do $$
declare v_variation_id uuid; v_invoice public.invoices; v_line_count int;
begin
  select id into v_variation_id from public.variation_orders where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  select * into v_invoice from public.create_variation_invoice(v_variation_id);
  if v_invoice.total_amount <> 2300 then raise exception 'FAIL: expected variation invoice total 2300 (2000 + 15%% tax), got %', v_invoice.total_amount; end if;
  select count(*) into v_line_count from public.invoice_lines where invoice_id = v_invoice.id;
  if v_line_count <> 1 then raise exception 'FAIL: expected 1 invoice line copied from the quote, got %', v_line_count; end if;
  raise notice 'PASS: create_variation_invoice copies the approved quote''s own line items into a real invoice with the same server-computed total (2300)';
end $$;

do $$
declare v_variation_id uuid;
begin
  select id into v_variation_id from public.variation_orders where client_id = '00000000-0000-0000-0000-000000006391' limit 1;
  begin
    perform public.create_variation_invoice(v_variation_id);
    raise exception 'SECURITY_FAILURE: an already-invoiced variation was invoiced a second time';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an already-invoiced variation cannot be invoiced again (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Contract billing: duplicate-period prevention, invoice tampering,
-- overpayment protection.

do $$
declare v_invoice public.invoices;
begin
  select * into v_invoice from public.generate_contract_billing_invoice('00000000-0000-0000-0000-000000006591', '2026-09-01', '2026-09-30');
  if v_invoice.total_amount <> 17250 then raise exception 'FAIL: expected contract billing total 17250 (15000 + 15%% tax), got %', v_invoice.total_amount; end if;
  raise notice 'PASS: generate_contract_billing_invoice derives the invoice from the contract''s own recurring_value (17250 = 15000 + 15%% tax)';
end $$;

do $$
begin
  begin
    perform public.generate_contract_billing_invoice('00000000-0000-0000-0000-000000006591', '2026-09-01', '2026-09-30');
    raise exception 'SECURITY_FAILURE: the same contract/billing-period was billed twice';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: duplicate billing for the same contract and billing period is rejected at the database level (%)', sqlerrm;
  end;
end $$;

do $$
declare v_invoice_id uuid;
begin
  select id into v_invoice_id from public.invoices where contract_id = '00000000-0000-0000-0000-000000006591' and source = 'contract_billing';
  begin
    update public.invoices set total_amount = 1 where id = v_invoice_id;
    raise exception 'SECURITY_FAILURE: invoices.total_amount was directly writable';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: invoices.total_amount cannot be directly forged even by an authorized manager (trigger-enforced protection) (%)', sqlerrm;
  end;
end $$;

do $$
declare v_invoice_id uuid; v_result public.invoices;
begin
  select id into v_invoice_id from public.invoices where contract_id = '00000000-0000-0000-0000-000000006591' and source = 'contract_billing';
  select * into v_result from public.issue_invoice(v_invoice_id, '2026-09-01', '2026-09-30');
  if v_result.status <> 'issued' or v_result.invoice_number is null then raise exception 'FAIL: expected issued with a real invoice_number, got status=%, number=%', v_result.status, v_result.invoice_number; end if;
  raise notice 'PASS: issue_invoice assigns a real, server-generated invoice_number (%)', v_result.invoice_number;
end $$;

do $$
declare v_invoice_id uuid;
begin
  select id into v_invoice_id from public.invoices where contract_id = '00000000-0000-0000-0000-000000006591' and source = 'contract_billing';
  begin
    perform public.record_payment(v_invoice_id, 99999, '2026-09-15');
    raise exception 'SECURITY_FAILURE: a payment exceeding the outstanding balance was accepted';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: overpayment beyond the outstanding balance is rejected (%)', sqlerrm;
  end;
end $$;

do $$
declare v_invoice_id uuid; v_result public.invoices;
begin
  select id into v_invoice_id from public.invoices where contract_id = '00000000-0000-0000-0000-000000006591' and source = 'contract_billing';
  select * into v_result from public.record_payment(v_invoice_id, 10000, '2026-09-15', 'eft', 'REF001');
  if v_result.status <> 'partially_paid' or v_result.amount_paid <> 10000 or v_result.amount_outstanding <> 7250 then
    raise exception 'FAIL: expected partially_paid, amount_paid=10000, outstanding=7250 — got status=%, paid=%, outstanding=%', v_result.status, v_result.amount_paid, v_result.amount_outstanding;
  end if;

  select * into v_result from public.record_payment(v_invoice_id, 7250, '2026-09-20', 'eft', 'REF002');
  if v_result.status <> 'paid' or v_result.amount_outstanding <> 0 then
    raise exception 'FAIL: expected paid with 0 outstanding after the final payment, got status=%, outstanding=%', v_result.status, v_result.amount_outstanding;
  end if;
  raise notice 'PASS: record_payment correctly transitions issued -> partially_paid -> paid as real payments accumulate, amount_outstanding is DB-generated (total - paid)';
end $$;

-- ---------------------------------------------------------------------------
-- Employee/worker isolation: a plain employee cannot see invoices/profitability.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006902","app_metadata":{"role":"employee"}}';

do $$
declare v_count int;
begin
  select count(*) into v_count from public.invoices;
  if v_count <> 0 then raise exception 'SECURITY_FAILURE: plain employee sees % invoices', v_count; end if;
  raise notice 'PASS: a plain employee (worker) cannot see any invoices';
end $$;

do $$
begin
  begin
    perform public.get_contract_profitability('00000000-0000-0000-0000-000000006591', '2026-09-01', '2026-09-30');
    raise exception 'SECURITY_FAILURE: plain employee accessed contract profitability';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee get_contract_profitability blocked (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006903","app_metadata":{"role":"client_user"}}';

do $$
begin
  begin
    perform public.get_contract_profitability('00000000-0000-0000-0000-000000006591', '2026-09-01', '2026-09-30');
    raise exception 'SECURITY_FAILURE: a client accessed internal contract profitability';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: a client (even the contract''s own client) cannot access internal profitability/cost data (%)', sqlerrm;
  end;
end $$;

do $$
declare v_count int;
begin
  select count(*) into v_count from public.invoices where client_id = '00000000-0000-0000-0000-000000006391';
  if v_count < 1 then raise exception 'FAIL: Client A should see their own invoice(s)'; end if;
  raise notice 'PASS: Client A can see their own invoices (client-facing visibility works correctly, distinct from internal profitability which stays hidden)';
end $$;

-- ---------------------------------------------------------------------------
-- Cross-tenant isolation on the new tables (org V2 has no relationship
-- to any of the above rows at all).

reset role;
reset request.jwt.claims;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000006905', 'authenticated', 'authenticated', 'admin-v2@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now());
insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000006905', '00000000-0000-0000-0000-000000000692', 'Admin', 'V2', 'admin-v2@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000006905","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_invoices int; v_variations int; v_requests int;
begin
  select count(*) into v_invoices from public.invoices where tenant_id = '00000000-0000-0000-0000-000000000691';
  select count(*) into v_variations from public.variation_orders where tenant_id = '00000000-0000-0000-0000-000000000691';
  select count(*) into v_requests from public.service_requests where tenant_id = '00000000-0000-0000-0000-000000000691';
  if v_invoices <> 0 or v_variations <> 0 or v_requests <> 0 then
    raise exception 'SECURITY_FAILURE: org V2 admin sees %/%/% of org V1''s invoices/variations/requests', v_invoices, v_variations, v_requests;
  end if;
  raise notice 'PASS: cross-tenant isolation holds for invoices/variation_orders/service_requests';
end $$;

rollback;
