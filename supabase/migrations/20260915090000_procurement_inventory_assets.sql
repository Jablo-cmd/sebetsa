-- Sebetsa Phase O — Procurement, Inventory & Asset Management, migration 1 of 2.
--
-- Operational resource management only — NOT a general ledger. Cost fields
-- (acquisition_cost, estimated_cost) support operational cost intelligence
-- (matching Sebetsa's existing Finance boundary), never full accounting:
-- no double-entry, no VAT, no bank reconciliation, no AP/AR here.
--
-- Three coordinated sub-domains, same can_manage_operations() write tier as
-- every other operational domain (Phase G/H/I/J/N):
--   1. Assets: a register with a lifecycle-enforced status and a permanent,
--      append-only assignment history (never overwritten/destroyed).
--   2. Inventory: items + an append-only movement ledger — current balance
--      is *derived* (summed) from the ledger, never a mutable quantity
--      column that could silently drift from its own history.
--   3. Procurement: a lightweight request-to-receipt workflow, explicitly
--      NOT accounts payable/general ledger.

create type public.asset_status as enum (
  'available', 'assigned', 'maintenance', 'lost', 'damaged', 'retired', 'disposed'
);

create type public.inventory_movement_type as enum (
  'receipt', 'issue', 'transfer_in', 'transfer_out', 'adjustment', 'return'
);

create type public.procurement_status as enum (
  'requested', 'submitted', 'approved', 'rejected', 'ordered', 'received', 'completed', 'cancelled'
);

-- ---------------------------------------------------------------------------
-- Assets.

create table public.assets (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  asset_number        text not null,
  name                text not null check (char_length(name) > 0),
  category            text not null check (char_length(category) > 0),
  serial_number       text,
  site_id             uuid references public.sites (id) on delete set null,
  custodian_employee_id uuid references public.employees (id) on delete set null,
  status              public.asset_status not null default 'available',
  condition           text,
  acquisition_date    date,
  acquisition_cost    numeric(12, 2) check (acquisition_cost is null or acquisition_cost >= 0),
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, asset_number)
);

comment on table public.assets is
  'custodian_employee_id/status are server-derived (assign_asset/return_asset/transition_asset_status RPCs only). acquisition_cost is operational cost intelligence, not an accounting ledger entry.';

create index assets_tenant_id_idx on public.assets (tenant_id);
create index assets_site_id_idx on public.assets (site_id);
create index assets_custodian_idx on public.assets (custodian_employee_id);
create index assets_status_idx on public.assets (status);

create trigger assets_set_updated_at
  before update on public.assets
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_asset_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if new.site_id is not null and not exists (select 1 from public.sites s where s.id = new.site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  if new.custodian_employee_id is not null and not exists (select 1 from public.employees e where e.id = new.custodian_employee_id and e.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.custodian_employee_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger assets_validate_tenant_refs
  before insert or update on public.assets
  for each row
  execute function public.validate_asset_tenant_refs();

-- Authoritative lifecycle.
create or replace function public.assets_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'available' and new.status in ('assigned', 'maintenance', 'lost', 'damaged', 'retired'))
    or (old.status = 'assigned' and new.status in ('available', 'maintenance', 'lost', 'damaged'))
    or (old.status = 'maintenance' and new.status in ('available', 'retired'))
    or (old.status = 'damaged' and new.status in ('maintenance', 'retired'))
    or (old.status = 'lost' and new.status in ('retired', 'available')) -- recovered
    or (old.status = 'retired' and new.status = 'disposed')
  ) then
    raise exception 'invalid_transition: cannot move asset from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger assets_validate_transition_trigger
  before update on public.assets
  for each row
  execute function public.assets_validate_transition();

alter table public.assets enable row level security;
alter table public.assets force row level security;

create policy assets_select on public.assets for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy assets_write on public.assets for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger assets_audit_log
  after insert or update on public.assets
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- Asset assignment history — permanent, append-only. `returned_at is null`
-- marks the current holder; history rows are never overwritten or deleted.

create table public.asset_assignments (
  id                    uuid primary key default gen_random_uuid(),
  tenant_id             uuid not null references public.organizations (id) on delete cascade,
  asset_id              uuid not null references public.assets (id) on delete cascade,
  assigned_to_employee_id uuid references public.employees (id) on delete set null,
  assigned_to_team_id   uuid references public.teams (id) on delete set null,
  assigned_to_site_id   uuid references public.sites (id) on delete set null,
  assigned_by           uuid references public.profiles (id) on delete set null,
  assigned_at           timestamptz not null default now(),
  returned_at           timestamptz,
  condition_at_assignment text,
  condition_at_return   text,
  reason                text,
  created_at            timestamptz not null default now(),
  check (
    (case when assigned_to_employee_id is not null then 1 else 0 end)
    + (case when assigned_to_team_id is not null then 1 else 0 end)
    + (case when assigned_to_site_id is not null then 1 else 0 end) = 1
  )
);

comment on table public.asset_assignments is
  'Append-only — no UPDATE/DELETE policy for authenticated. returned_at is set exactly once, by return_asset(), never cleared.';

create index asset_assignments_asset_idx on public.asset_assignments (asset_id);
create index asset_assignments_open_idx on public.asset_assignments (asset_id) where returned_at is null;

alter table public.asset_assignments enable row level security;
alter table public.asset_assignments force row level security;

create policy asset_assignments_select on public.asset_assignments for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

-- No direct client write — assign_asset()/return_asset() RPCs only.

-- ---------------------------------------------------------------------------
-- Maintenance history — a permanent log, independent of the status trigger
-- above (a manager may log maintenance work without necessarily moving the
-- asset in and out of 'maintenance' status for a minor service).

create table public.asset_maintenance_records (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  asset_id      uuid not null references public.assets (id) on delete cascade,
  description   text not null check (char_length(description) > 0),
  performed_at  date not null default current_date,
  cost          numeric(12, 2) check (cost is null or cost >= 0),
  performed_by  uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

create index asset_maintenance_records_asset_idx on public.asset_maintenance_records (asset_id);

alter table public.asset_maintenance_records enable row level security;
alter table public.asset_maintenance_records force row level security;

create policy asset_maintenance_records_select on public.asset_maintenance_records for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

-- No direct client write — record_asset_maintenance() RPC only.

-- ---------------------------------------------------------------------------
-- Inventory: items + an append-only movement ledger. Current balance is
-- derived (summed) from the ledger via get_inventory_balance() — never a
-- mutable quantity column that could drift from its own history.

create table public.inventory_items (
  id                  uuid primary key default gen_random_uuid(),
  tenant_id           uuid not null references public.organizations (id) on delete cascade,
  sku                 text not null,
  name                text not null check (char_length(name) > 0),
  category            text not null check (char_length(category) > 0),
  unit                text not null default 'each',
  reorder_threshold   numeric(12, 2) check (reorder_threshold is null or reorder_threshold >= 0),
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, sku)
);

create index inventory_items_tenant_id_idx on public.inventory_items (tenant_id);

create trigger inventory_items_set_updated_at
  before update on public.inventory_items
  for each row
  execute function public.set_updated_at();

alter table public.inventory_items enable row level security;
alter table public.inventory_items force row level security;

create policy inventory_items_select on public.inventory_items for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

create policy inventory_items_write on public.inventory_items for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger inventory_items_audit_log
  after insert or update on public.inventory_items
  for each row
  execute function public.audit_log_from_trigger();

create table public.inventory_movements (
  id            uuid primary key default gen_random_uuid(),
  tenant_id     uuid not null references public.organizations (id) on delete cascade,
  item_id       uuid not null references public.inventory_items (id) on delete cascade,
  site_id       uuid not null references public.sites (id) on delete cascade,
  movement_type public.inventory_movement_type not null,
  quantity      numeric(12, 2) not null check (quantity > 0),
  reference     text,
  performed_by  uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

comment on table public.inventory_movements is
  'Append-only signed ledger: receipt/transfer_in/return/adjustment increase a site''s balance, issue/transfer_out decrease it — quantity itself is always stored positive, movement_type carries the sign. A stock write-off/correction downward is recorded as an `issue` with a descriptive reference (e.g. "adjustment: stock count correction"), keeping only two sign buckets rather than a third ambiguous direction. No UPDATE/DELETE policy.';

create index inventory_movements_item_site_idx on public.inventory_movements (item_id, site_id);
create index inventory_movements_tenant_id_idx on public.inventory_movements (tenant_id);

create or replace function public.validate_inventory_movement_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.inventory_items i where i.id = new.item_id and i.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: inventory item % does not belong to tenant %', new.item_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.sites s where s.id = new.site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger inventory_movements_validate_tenant_refs
  before insert on public.inventory_movements
  for each row
  execute function public.validate_inventory_movement_tenant_refs();

alter table public.inventory_movements enable row level security;
alter table public.inventory_movements force row level security;

create policy inventory_movements_select on public.inventory_movements for select to authenticated
  using (tenant_id = public.current_tenant_id() or public.is_platform_admin());

-- No direct client write — record_inventory_movement() RPC only.

-- SECURITY INVOKER (default) — runs under the caller's own privileges, so
-- it can never see more than that caller's own RLS-scoped movements; not a
-- privilege-escalation path.
create or replace function public.get_inventory_balance(p_item_id uuid, p_site_id uuid)
returns numeric
language sql
stable
as $$
  select coalesce(sum(
    case when movement_type in ('receipt', 'transfer_in', 'return', 'adjustment') then quantity
         when movement_type in ('issue', 'transfer_out') then -quantity
    end
  ), 0)
  from public.inventory_movements
  where item_id = p_item_id and site_id = p_site_id;
$$;

revoke execute on function public.get_inventory_balance(uuid, uuid) from public, anon;
grant execute on function public.get_inventory_balance(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Procurement requests — a lightweight operational workflow, explicitly not
-- accounts payable/general ledger.

create table public.procurement_requests (
  id                uuid primary key default gen_random_uuid(),
  tenant_id         uuid not null references public.organizations (id) on delete cascade,
  requested_by      uuid references public.profiles (id) on delete set null,
  site_id           uuid references public.sites (id) on delete set null,
  item_description  text not null check (char_length(item_description) > 0),
  quantity          numeric(12, 2) not null check (quantity > 0),
  estimated_cost    numeric(12, 2) check (estimated_cost is null or estimated_cost >= 0),
  status            public.procurement_status not null default 'requested',
  approved_by       uuid references public.profiles (id) on delete set null,
  approved_at       timestamptz,
  rejected_reason   text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.procurement_requests is
  'status/approved_by/approved_at are server-derived (submit_procurement_request/decide_procurement_request/advance_procurement_request RPCs only).';

create index procurement_requests_tenant_id_idx on public.procurement_requests (tenant_id);
create index procurement_requests_status_idx on public.procurement_requests (status);
create index procurement_requests_requested_by_idx on public.procurement_requests (requested_by);

create trigger procurement_requests_set_updated_at
  before update on public.procurement_requests
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_procurement_request_tenant_ref()
returns trigger
language plpgsql
as $$
begin
  if new.site_id is not null and not exists (select 1 from public.sites s where s.id = new.site_id and s.tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger procurement_requests_validate_tenant_ref
  before insert or update on public.procurement_requests
  for each row
  execute function public.validate_procurement_request_tenant_ref();

create or replace function public.procurement_requests_validate_transition()
returns trigger
language plpgsql
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'requested' and new.status in ('submitted', 'cancelled'))
    or (old.status = 'submitted' and new.status in ('approved', 'rejected', 'cancelled'))
    or (old.status = 'approved' and new.status = 'ordered')
    or (old.status = 'ordered' and new.status = 'received')
    or (old.status = 'received' and new.status = 'completed')
  ) then
    raise exception 'invalid_transition: cannot move procurement request from % to %', old.status, new.status;
  end if;

  return new;
end;
$$;

create trigger procurement_requests_validate_transition_trigger
  before update on public.procurement_requests
  for each row
  execute function public.procurement_requests_validate_transition();

alter table public.procurement_requests enable row level security;
alter table public.procurement_requests force row level security;

create policy procurement_requests_select on public.procurement_requests for select to authenticated
  using (
    requested_by = auth.uid()
    or public.can_manage_operations(tenant_id)
  );

-- No direct client write — submit_procurement_request()/decide_procurement_
-- request()/advance_procurement_request() RPCs only.

create trigger procurement_requests_audit_log
  after insert or update on public.procurement_requests
  for each row
  execute function public.audit_log_from_trigger();
