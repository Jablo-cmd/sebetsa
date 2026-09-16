-- Sebetsa Phase R — Quoting & Proposals: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/quotes.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000491', 'Org R1', 'active'),
  ('00000000-0000-0000-0000-000000000492', 'Org R2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004901', 'authenticated', 'authenticated', 'admin-r1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000004902', 'authenticated', 'authenticated', 'employee-r1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000004901', '00000000-0000-0000-0000-000000000491', 'Admin', 'R1', 'admin-r1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000004902', '00000000-0000-0000-0000-000000000491', 'Emp', 'R1', 'employee-r1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004901","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000004391', '00000000-0000-0000-0000-000000000491', 'Client R1');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004491', '00000000-0000-0000-0000-000000000491', '00000000-0000-0000-0000-000000004391', 'Site R1');

reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000004392', '00000000-0000-0000-0000-000000000492', 'Client R2');

-- ---------------------------------------------------------------------------
-- Quote creation + tenant isolation.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004901","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    insert into public.quotes (tenant_id, client_id, quote_number)
    values ('00000000-0000-0000-0000-000000000491', '00000000-0000-0000-0000-000000004392', 'QT-BAD');
    raise exception 'SECURITY_FAILURE: cross-tenant quotes.client_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant quotes.client_id blocked (%)', sqlerrm;
  end;
end $$;

insert into public.quotes (id, tenant_id, client_id, site_id, quote_number, tax_rate)
values ('00000000-0000-0000-0000-000000005491', '00000000-0000-0000-0000-000000000491', '00000000-0000-0000-0000-000000004391', '00000000-0000-0000-0000-000000004491', 'QT-001', 15);

-- ---------------------------------------------------------------------------
-- Line items: DB-generated line_total, server-recomputed quote totals.

insert into public.quote_line_items (tenant_id, quote_id, category, description, quantity, unit_rate)
values
  ('00000000-0000-0000-0000-000000000491', '00000000-0000-0000-0000-000000005491', 'labour', 'Cleaning labour', 100, 150),
  ('00000000-0000-0000-0000-000000000491', '00000000-0000-0000-0000-000000005491', 'consumables', 'Consumables', 1, 5000);

do $$
declare v_total numeric;
begin
  select line_total into v_total from public.quote_line_items where description = 'Cleaning labour';
  if v_total <> 15000 then raise exception 'FAIL: expected DB-generated line_total 15000 (100 x 150), got %', v_total; end if;
  raise notice 'PASS: quote_line_items.line_total is a DB-generated column (quantity x unit_rate), never client-supplied';
end $$;

do $$
begin
  begin
    update public.quote_line_items set line_total = 1 where description = 'Cleaning labour';
    raise exception 'SECURITY_FAILURE: line_total was directly writable';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: line_total cannot be directly written (generated column) (%)', sqlerrm;
  end;
end $$;

do $$
declare v_subtotal numeric; v_tax numeric; v_total numeric;
begin
  select subtotal, tax_amount, total_amount into v_subtotal, v_tax, v_total
    from public.recompute_quote_totals('00000000-0000-0000-0000-000000005491');
  if v_subtotal <> 20000 then raise exception 'FAIL: expected subtotal 20000 (15000 + 5000), got %', v_subtotal; end if;
  if v_tax <> 3000 then raise exception 'FAIL: expected tax 3000 (15%% of 20000), got %', v_tax; end if;
  if v_total <> 23000 then raise exception 'FAIL: expected total 23000, got %', v_total; end if;
  raise notice 'PASS: recompute_quote_totals derives subtotal/tax/total from the real line items (20000 + 15%% tax = 23000)';
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004902","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.recompute_quote_totals('00000000-0000-0000-0000-000000005491');
    raise exception 'SECURITY_FAILURE: plain employee recomputed quote totals';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee recompute_quote_totals blocked (%)', sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- Status lifecycle.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000004901","app_metadata":{"role":"organization_administrator"}}';

do $$
begin
  begin
    update public.quotes set status = 'approved' where id = '00000000-0000-0000-0000-000000005491';
    raise exception 'SECURITY_FAILURE: illegal quote jump (draft -> approved) succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: illegal quote status jump blocked (%)', sqlerrm;
  end;
end $$;

update public.quotes set status = 'sent' where id = '00000000-0000-0000-0000-000000005491';
update public.quotes set status = 'viewed' where id = '00000000-0000-0000-0000-000000005491';

-- ---------------------------------------------------------------------------
-- convert_quote_to_contract: only an approved quote converts, exactly once.

do $$
begin
  begin
    perform public.convert_quote_to_contract('00000000-0000-0000-0000-000000005491', 'CTR-FROM-QUOTE', '2026-10-01');
    raise exception 'SECURITY_FAILURE: a non-approved (viewed) quote was converted to a contract';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: converting a non-approved quote is rejected (%)', sqlerrm;
  end;
end $$;

update public.quotes set status = 'approved' where id = '00000000-0000-0000-0000-000000005491';

do $$
declare v_contract public.contracts; v_site_count int;
begin
  select * into v_contract from public.convert_quote_to_contract('00000000-0000-0000-0000-000000005491', 'CTR-FROM-QUOTE', '2026-10-01');
  if v_contract.contract_value <> 23000 then raise exception 'FAIL: expected new contract.contract_value = quote.total_amount (23000), got %', v_contract.contract_value; end if;
  if v_contract.status <> 'draft' then raise exception 'FAIL: expected new contract.status = draft, got %', v_contract.status; end if;
  select count(*) into v_site_count from public.contract_sites where contract_id = v_contract.id and site_id = '00000000-0000-0000-0000-000000004491';
  if v_site_count <> 1 then raise exception 'FAIL: expected the quote''s site to be linked via contract_sites, got % rows', v_site_count; end if;
  raise notice 'PASS: convert_quote_to_contract creates a real contract with the quote''s own server-computed total_amount as contract_value, linked to the quote''s site';
end $$;

do $$
begin
  begin
    perform public.convert_quote_to_contract('00000000-0000-0000-0000-000000005491', 'CTR-DOUBLE', '2026-10-01');
    raise exception 'SECURITY_FAILURE: an already-converted quote was converted a second time';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: an already-converted quote cannot be converted again (%)', sqlerrm;
  end;
end $$;

do $$
declare v_converted uuid;
begin
  select converted_to_contract_id into v_converted from public.quotes where id = '00000000-0000-0000-0000-000000005491';
  if v_converted is null then raise exception 'FAIL: quotes.converted_to_contract_id was not set after conversion'; end if;
  raise notice 'PASS: quotes.converted_to_contract_id records the resulting contract';
end $$;

-- ---------------------------------------------------------------------------
-- Append-only audit check for the conversion.

do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'quotes' and action = 'quote_converted_to_contract';
  if v_count < 1 then raise exception 'FAIL: quote-to-contract conversion was not audit-logged'; end if;
  select count(*) into v_count from public.audit_log where entity_table = 'contracts' and action = 'contract_created_from_quote';
  if v_count < 1 then raise exception 'FAIL: the resulting contract creation was not audit-logged'; end if;
  raise notice 'PASS: quote-to-contract conversion is audit-logged on both sides';
end $$;

rollback;
