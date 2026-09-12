-- Sebetsa Phase O — Procurement, Inventory & Asset Management: RLS/RPC checks.
--
--   supabase start
--   cat supabase/rls-tests/procurement_inventory_assets.sql | docker exec -i supabase_db_sebetsa psql -U postgres -d postgres
--
-- One transaction, always rolled back.

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-000000000291', 'Org O1', 'active'),
  ('00000000-0000-0000-0000-000000000292', 'Org O2', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000002901', 'authenticated', 'authenticated', 'admin-o1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"organization_administrator"}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000002902', 'authenticated', 'authenticated', 'employee-o1@example.com', crypt('x', gen_salt('bf')), now(), '{"role":"employee"}', '{}', now(), now());

insert into public.profiles (id, tenant_id, first_name, last_name, email, status) values
  ('00000000-0000-0000-0000-000000002901', '00000000-0000-0000-0000-000000000291', 'Admin', 'O1', 'admin-o1@example.com', 'active'),
  ('00000000-0000-0000-0000-000000002902', '00000000-0000-0000-0000-000000000291', 'Emp', 'O1', 'employee-o1@example.com', 'active');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002901","app_metadata":{"role":"organization_administrator"}}';

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003291', '00000000-0000-0000-0000-000000000291', 'Client O1');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004291', '00000000-0000-0000-0000-000000000291', '00000000-0000-0000-0000-000000003291', 'Site O1');
insert into public.employees (id, tenant_id, profile_id, employee_number, first_name, last_name, employment_status) values
  ('00000000-0000-0000-0000-000000005291', '00000000-0000-0000-0000-000000000291', '00000000-0000-0000-0000-000000002902', 'EMP-O1', 'Emp', 'O1', 'active');

reset role;
reset request.jwt.claims;
insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-000000003292', '00000000-0000-0000-0000-000000000292', 'Client O2');
insert into public.sites (id, tenant_id, client_id, name) values ('00000000-0000-0000-0000-000000004292', '00000000-0000-0000-0000-000000000292', '00000000-0000-0000-0000-000000003292', 'Site O2');

-- ---------------------------------------------------------------------------
-- Assets: create (direct write — manager tier), assign, return, lifecycle.

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002901","app_metadata":{"role":"organization_administrator"}}';

insert into public.assets (id, tenant_id, asset_number, name, category, site_id)
values ('00000000-0000-0000-0000-000000006291', '00000000-0000-0000-0000-000000000291', 'AST-001', 'Floor Buffer', 'equipment', '00000000-0000-0000-0000-000000004291');

do $$
begin
  begin
    insert into public.assets (tenant_id, asset_number, name, category, site_id)
    values ('00000000-0000-0000-0000-000000000291', 'AST-002', 'Cross-tenant asset', 'equipment', '00000000-0000-0000-0000-000000004292');
    raise exception 'SECURITY_FAILURE: cross-tenant asset.site_id insert succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cross-tenant asset.site_id blocked (%)', sqlerrm;
  end;
end $$;

do $$
declare v_status public.asset_status;
begin
  select status into v_status from public.assign_asset('00000000-0000-0000-0000-000000006291', '00000000-0000-0000-0000-000000005291', null, null, 'good', 'daily cleaning duty');
  if v_status <> 'assigned' then raise exception 'FAIL: expected assigned, got %', v_status; end if;
  raise notice 'PASS: assign_asset moves an available asset to assigned';
end $$;

do $$
begin
  begin
    perform public.assign_asset('00000000-0000-0000-0000-000000006291', '00000000-0000-0000-0000-000000005291');
    raise exception 'SECURITY_FAILURE: assigned an already-assigned asset';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: cannot assign an already-assigned asset (%)', sqlerrm;
  end;
end $$;

do $$
declare v_status public.asset_status; v_count int;
begin
  select status into v_status from public.return_asset('00000000-0000-0000-0000-000000006291', 'fair', 'available');
  if v_status <> 'available' then raise exception 'FAIL: expected available after return, got %', v_status; end if;

  select count(*) into v_count from public.asset_assignments where asset_id = '00000000-0000-0000-0000-000000006291' and returned_at is not null;
  if v_count <> 1 then raise exception 'FAIL: expected 1 closed assignment record, got %', v_count; end if;
  raise notice 'PASS: return_asset closes the assignment and restores availability, history preserved';
end $$;

do $$
begin
  begin
    perform public.transition_asset_status('00000000-0000-0000-0000-000000006291', 'disposed');
    raise exception 'SECURITY_FAILURE: illegal asset status jump (available -> disposed) succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: illegal asset status jump blocked (%)', sqlerrm;
  end;
end $$;

-- Employee cannot manage assets.
reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002902","app_metadata":{"role":"employee"}}';

do $$
begin
  begin
    perform public.assign_asset('00000000-0000-0000-0000-000000006291', '00000000-0000-0000-0000-000000005291');
    raise exception 'SECURITY_FAILURE: plain employee assigned an asset';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee assign_asset blocked (%)', sqlerrm;
  end;
end $$;

do $$
declare v_rows int;
begin
  update public.assets set name = 'hacked' where id = '00000000-0000-0000-0000-000000006291';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'SECURITY_FAILURE: employee updated an asset directly (% rows)', v_rows; end if;
  raise notice 'PASS: employee direct UPDATE of assets affects 0 rows (RLS hides it)';
end $$;

-- ---------------------------------------------------------------------------
-- Inventory: movements, derived balance, negative-stock guard.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002901","app_metadata":{"role":"organization_administrator"}}';

insert into public.inventory_items (id, tenant_id, sku, name, category)
values ('00000000-0000-0000-0000-000000007291', '00000000-0000-0000-0000-000000000291', 'SKU-001', 'Disinfectant 5L', 'consumables');

do $$
declare v_balance numeric;
begin
  perform public.record_inventory_movement('00000000-0000-0000-0000-000000007291', '00000000-0000-0000-0000-000000004291', 'receipt', 20, 'initial stock');
  select public.get_inventory_balance('00000000-0000-0000-0000-000000007291', '00000000-0000-0000-0000-000000004291') into v_balance;
  if v_balance <> 20 then raise exception 'FAIL: expected balance 20 after receipt, got %', v_balance; end if;
  raise notice 'PASS: receipt movement increases derived balance to 20';
end $$;

do $$
declare v_balance numeric;
begin
  perform public.record_inventory_movement('00000000-0000-0000-0000-000000007291', '00000000-0000-0000-0000-000000004291', 'issue', 5, 'site consumption');
  select public.get_inventory_balance('00000000-0000-0000-0000-000000007291', '00000000-0000-0000-0000-000000004291') into v_balance;
  if v_balance <> 15 then raise exception 'FAIL: expected balance 15 after issue, got %', v_balance; end if;
  raise notice 'PASS: issue movement decreases derived balance to 15';
end $$;

do $$
begin
  begin
    perform public.record_inventory_movement('00000000-0000-0000-0000-000000007291', '00000000-0000-0000-0000-000000004291', 'issue', 999, 'attempted overdraw');
    raise exception 'SECURITY_FAILURE: issue movement drove balance negative without override';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: negative-stock guard blocks an overdrawing issue movement (%)', sqlerrm;
  end;
end $$;

do $$
declare v_rows int;
begin
  update public.inventory_movements set quantity = 999 where item_id = '00000000-0000-0000-0000-000000007291';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'SECURITY_FAILURE: direct UPDATE of an inventory movement succeeded (% rows)', v_rows; end if;
  raise notice 'PASS: inventory_movements is append-only (direct UPDATE affects 0 rows)';
end $$;

-- ---------------------------------------------------------------------------
-- Procurement: submit, self-approval block, approve, advance.

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002902","app_metadata":{"role":"employee"}}';

do $$
declare v_id uuid; v_status public.procurement_status;
begin
  select id, status into v_id, v_status from public.submit_procurement_request(
    '00000000-0000-0000-0000-000000000291', 'Replacement mop heads', 10, '00000000-0000-0000-0000-000000004291', 150.00
  );
  if v_status <> 'submitted' then raise exception 'FAIL: expected submitted, got %', v_status; end if;
  raise notice 'PASS: employee can submit a procurement request (%)', v_id;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002902","app_metadata":{"role":"employee"}}';

do $$
declare v_id uuid;
begin
  select id into v_id from public.procurement_requests where tenant_id = '00000000-0000-0000-0000-000000000291' limit 1;
  begin
    perform public.decide_procurement_request(v_id, true);
    raise exception 'SECURITY_FAILURE: plain employee decided a procurement request';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: plain-employee decide_procurement_request blocked (%)', sqlerrm;
  end;
end $$;

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000002901","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_id uuid; v_status public.procurement_status;
begin
  select id into v_id from public.procurement_requests where tenant_id = '00000000-0000-0000-0000-000000000291' limit 1;
  select status into v_status from public.decide_procurement_request(v_id, true);
  if v_status <> 'approved' then raise exception 'FAIL: expected approved, got %', v_status; end if;
  raise notice 'PASS: manager can approve a submitted procurement request';

  select status into v_status from public.advance_procurement_request(v_id, 'ordered');
  if v_status <> 'ordered' then raise exception 'FAIL: expected ordered, got %', v_status; end if;

  begin
    perform public.advance_procurement_request(v_id, 'completed');
    raise exception 'SECURITY_FAILURE: illegal procurement jump (ordered -> completed) succeeded';
  exception
    when others then
      if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
      raise notice 'PASS: illegal procurement status jump blocked (%)', sqlerrm;
  end;
end $$;

-- Append-only audit check.
reset role;
reset request.jwt.claims;
do $$
declare v_count int;
begin
  select count(*) into v_count from public.audit_log where entity_table = 'assets' and action = 'asset_assigned';
  if v_count < 1 then raise exception 'FAIL: asset assignment was not audit-logged'; end if;
  raise notice 'PASS: asset assignment is audit-logged';
end $$;

rollback;
