-- Sebetsa Phase O — Procurement, Inventory & Asset Management, migration 2 of 2.
--
-- RPCs following the exact Phase H/M/N shape: auth check, permission check
-- via can_manage_operations(), row lock before any status-dependent write,
-- server-derived actor/timestamp fields, write_audit_log() call, explicit
-- EXECUTE grants (Phase H lesson: revoke from public/anon, grant only to
-- authenticated).

-- ---------------------------------------------------------------------------
-- Assets: assignment/return, closing any prior open assignment atomically.

create or replace function public.assign_asset(
  p_asset_id              uuid,
  p_assigned_to_employee_id uuid default null,
  p_assigned_to_team_id     uuid default null,
  p_assigned_to_site_id     uuid default null,
  p_condition               text default null,
  p_reason                  text default null
) returns public.assets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_status public.asset_status;
  v_result public.assets;
begin
  select tenant_id, status into v_tenant_id, v_status from public.assets where id = p_asset_id for update;
  if not found then
    raise exception 'not_found: no asset %', p_asset_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot assign this asset';
  end if;

  if v_status not in ('available') then
    raise exception 'invalid_transition: asset must be available to assign (currently %)', v_status;
  end if;

  insert into public.asset_assignments (
    tenant_id, asset_id, assigned_to_employee_id, assigned_to_team_id, assigned_to_site_id,
    assigned_by, condition_at_assignment, reason
  ) values (
    v_tenant_id, p_asset_id, p_assigned_to_employee_id, p_assigned_to_team_id, p_assigned_to_site_id,
    auth.uid(), p_condition, p_reason
  );

  update public.assets
    set status = 'assigned',
        custodian_employee_id = p_assigned_to_employee_id,
        condition = coalesce(p_condition, condition)
    where id = p_asset_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'asset_assigned', 'assets', p_asset_id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.assign_asset(uuid, uuid, uuid, uuid, text, text) from public, anon;
grant execute on function public.assign_asset(uuid, uuid, uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.return_asset(
  p_asset_id            uuid,
  p_condition_at_return text default null,
  p_new_status          public.asset_status default 'available'
) returns public.assets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_status public.asset_status;
  v_result public.assets;
begin
  select tenant_id, status into v_tenant_id, v_status from public.assets where id = p_asset_id for update;
  if not found then
    raise exception 'not_found: no asset %', p_asset_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot return this asset';
  end if;

  if v_status <> 'assigned' then
    raise exception 'invalid_transition: asset is not currently assigned (status %)', v_status;
  end if;

  if p_new_status not in ('available', 'maintenance', 'lost', 'damaged') then
    raise exception 'invalid_transition: % is not a valid return status', p_new_status;
  end if;

  update public.asset_assignments
    set returned_at = now(), condition_at_return = p_condition_at_return
    where asset_id = p_asset_id and returned_at is null;

  update public.assets
    set status = p_new_status,
        custodian_employee_id = null,
        condition = coalesce(p_condition_at_return, condition)
    where id = p_asset_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'asset_returned', 'assets', p_asset_id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.return_asset(uuid, text, public.asset_status) from public, anon;
grant execute on function public.return_asset(uuid, text, public.asset_status) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.transition_asset_status(p_asset_id uuid, p_new_status public.asset_status)
returns public.assets
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_old_status public.asset_status;
  v_result public.assets;
begin
  select tenant_id, status into v_tenant_id, v_old_status from public.assets where id = p_asset_id for update;
  if not found then
    raise exception 'not_found: no asset %', p_asset_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot change this asset''s status';
  end if;

  update public.assets set status = p_new_status where id = p_asset_id returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'asset_status_changed', 'assets', p_asset_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status)
  );

  return v_result;
end;
$$;

revoke execute on function public.transition_asset_status(uuid, public.asset_status) from public, anon;
grant execute on function public.transition_asset_status(uuid, public.asset_status) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.record_asset_maintenance(
  p_asset_id     uuid,
  p_description  text,
  p_cost         numeric default null,
  p_performed_at date default current_date
) returns public.asset_maintenance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.asset_maintenance_records;
begin
  select tenant_id into v_tenant_id from public.assets where id = p_asset_id;
  if not found then
    raise exception 'not_found: no asset %', p_asset_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot log maintenance for this asset';
  end if;

  insert into public.asset_maintenance_records (tenant_id, asset_id, description, cost, performed_at, performed_by)
  values (v_tenant_id, p_asset_id, p_description, p_cost, p_performed_at, auth.uid())
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'asset_maintenance_logged', 'asset_maintenance_records', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.record_asset_maintenance(uuid, text, numeric, date) from public, anon;
grant execute on function public.record_asset_maintenance(uuid, text, numeric, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Inventory movements — the append-only ledger write path. Blocks a
-- decreasing movement (issue/transfer_out) that would drive the site's
-- balance negative, unless p_allow_negative is explicitly passed (a
-- deliberate, audited override — never a silent default).

create or replace function public.record_inventory_movement(
  p_item_id         uuid,
  p_site_id         uuid,
  p_movement_type   public.inventory_movement_type,
  p_quantity        numeric,
  p_reference       text default null,
  p_allow_negative  boolean default false
) returns public.inventory_movements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_current_balance numeric;
  v_result public.inventory_movements;
begin
  select tenant_id into v_tenant_id from public.inventory_items where id = p_item_id;
  if not found then
    raise exception 'not_found: no inventory item %', p_item_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot record movements for this tenant';
  end if;

  if p_movement_type in ('issue', 'transfer_out') and not p_allow_negative then
    v_current_balance := public.get_inventory_balance(p_item_id, p_site_id);
    if v_current_balance - p_quantity < 0 then
      raise exception 'insufficient_stock: % available at this site, % requested', v_current_balance, p_quantity;
    end if;
  end if;

  insert into public.inventory_movements (tenant_id, item_id, site_id, movement_type, quantity, reference, performed_by)
  values (v_tenant_id, p_item_id, p_site_id, p_movement_type, p_quantity, p_reference, auth.uid())
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'inventory_movement_recorded', 'inventory_movements', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.record_inventory_movement(uuid, uuid, public.inventory_movement_type, numeric, text, boolean) from public, anon;
grant execute on function public.record_inventory_movement(uuid, uuid, public.inventory_movement_type, numeric, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Procurement lifecycle.

create or replace function public.submit_procurement_request(
  p_tenant_id       uuid,
  p_item_description text,
  p_quantity        numeric,
  p_site_id         uuid default null,
  p_estimated_cost  numeric default null
) returns public.procurement_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result public.procurement_requests;
begin
  if p_tenant_id <> public.current_tenant_id() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot submit a procurement request for another tenant';
  end if;

  insert into public.procurement_requests (tenant_id, requested_by, site_id, item_description, quantity, estimated_cost, status)
  values (p_tenant_id, auth.uid(), p_site_id, p_item_description, p_quantity, p_estimated_cost, 'submitted')
  returning * into v_result;

  perform public.write_audit_log(p_tenant_id, auth.uid(), 'procurement_request_submitted', 'procurement_requests', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.submit_procurement_request(uuid, text, numeric, uuid, numeric) from public, anon;
grant execute on function public.submit_procurement_request(uuid, text, numeric, uuid, numeric) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.decide_procurement_request(
  p_request_id uuid,
  p_approve    boolean,
  p_rejected_reason text default null
) returns public.procurement_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_requested_by uuid;
  v_status public.procurement_status;
  v_result public.procurement_requests;
begin
  select tenant_id, requested_by, status into v_tenant_id, v_requested_by, v_status
  from public.procurement_requests where id = p_request_id for update;

  if not found then
    raise exception 'not_found: no procurement request %', p_request_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot decide this procurement request';
  end if;

  if v_requested_by = auth.uid() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot approve your own procurement request';
  end if;

  if v_status <> 'submitted' then
    raise exception 'invalid_transition: request must be submitted to decide on it (currently %)', v_status;
  end if;

  update public.procurement_requests
    set status = case when p_approve then 'approved'::public.procurement_status else 'rejected'::public.procurement_status end,
        approved_by = case when p_approve then auth.uid() else approved_by end,
        approved_at = case when p_approve then now() else approved_at end,
        rejected_reason = case when p_approve then null else p_rejected_reason end
    where id = p_request_id
    returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'procurement_request_decided', 'procurement_requests', p_request_id,
    jsonb_build_object('status', v_status), jsonb_build_object('status', v_result.status)
  );

  return v_result;
end;
$$;

revoke execute on function public.decide_procurement_request(uuid, boolean, text) from public, anon;
grant execute on function public.decide_procurement_request(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Single-step advance for the mechanical, non-decision part of the
-- lifecycle (approved -> ordered -> received -> completed): no separate
-- authorization nuance beyond can_manage_operations() at each step.

create or replace function public.advance_procurement_request(p_request_id uuid, p_new_status public.procurement_status)
returns public.procurement_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_old_status public.procurement_status;
  v_result public.procurement_requests;
begin
  select tenant_id, status into v_tenant_id, v_old_status from public.procurement_requests where id = p_request_id for update;
  if not found then
    raise exception 'not_found: no procurement request %', p_request_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot advance this procurement request';
  end if;

  update public.procurement_requests set status = p_new_status where id = p_request_id returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'procurement_request_advanced', 'procurement_requests', p_request_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status)
  );

  return v_result;
end;
$$;

revoke execute on function public.advance_procurement_request(uuid, public.procurement_status) from public, anon;
grant execute on function public.advance_procurement_request(uuid, public.procurement_status) to authenticated;
