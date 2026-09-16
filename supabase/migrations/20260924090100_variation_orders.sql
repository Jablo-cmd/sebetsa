-- Sebetsa Phase U — Variation Orders / Additional Work.
--
-- SERVICE REQUEST -> ASSESSMENT -> VARIATION -> (existing) QUOTE ->
-- CLIENT APPROVAL -> WORK ORDER -> COMPLETION -> (Phase V) INVOICE.
--
-- Reuses the existing quotes/quote_line_items engine unchanged for
-- pricing (a variation's quote_id points at a real row in the same
-- `quotes` table sales quotes use — no second line-item/total system) and
-- the existing `tasks` table for the work order (a variation's task_id
-- points at a real row in `tasks` — no second work-assignment system).
-- variation_orders never calls convert_quote_to_contract(): that RPC is
-- reserved for turning a NEW sales quote into a NEW contract. A variation
-- attaches billable work to an EXISTING contract instead.

create type public.service_request_type as enum ('additional_cleaning', 'deep_clean', 'complaint', 'emergency', 'other');
create type public.service_request_status as enum ('requested', 'assessed', 'converted', 'rejected', 'cancelled');
create type public.service_request_origin as enum ('client', 'internal');
create type public.variation_order_status as enum (
  'draft', 'assessed', 'quoting', 'quoted', 'approved', 'rejected',
  'scheduled', 'in_progress', 'completed', 'invoiced', 'cancelled'
);

-- ---------------------------------------------------------------------------
create table public.service_requests (
  id             uuid primary key default gen_random_uuid(),
  tenant_id      uuid not null references public.organizations (id) on delete cascade,
  client_id      uuid not null references public.clients (id) on delete cascade,
  site_id        uuid references public.sites (id) on delete set null,
  contract_id    uuid references public.contracts (id) on delete set null,
  requested_by   uuid references public.profiles (id) on delete set null,
  request_type   public.service_request_type not null default 'other',
  description    text not null check (char_length(description) > 0),
  requested_date date,
  priority       public.task_priority not null default 'normal',
  status         public.service_request_status not null default 'requested',
  origin         public.service_request_origin not null default 'internal',
  resolved_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.service_requests is
  'The front door for work outside a contract''s existing scope — submitted by a client (origin=client, via submit_service_request()) or raised internally. Converts into a variation_orders row via assess_service_request(); never auto-converts.';

create index service_requests_tenant_id_idx on public.service_requests (tenant_id);
create index service_requests_client_id_idx on public.service_requests (client_id);
create index service_requests_status_idx on public.service_requests (status);

create trigger service_requests_set_updated_at
  before update on public.service_requests
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_service_request_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  if new.site_id is not null and not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: site % does not belong to client %', new.site_id, new.client_id;
  end if;
  if new.contract_id is not null and not exists (select 1 from public.contracts where id = new.contract_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: contract % does not belong to client %', new.contract_id, new.client_id;
  end if;
  return new;
end;
$$;

create trigger service_requests_validate_tenant_refs
  before insert or update on public.service_requests
  for each row
  execute function public.validate_service_request_tenant_refs();

alter table public.service_requests enable row level security;
alter table public.service_requests force row level security;

create policy service_requests_select on public.service_requests for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or client_id = public.current_client_id()
    or public.is_platform_admin()
  );

-- Internal staff may create/update directly; client submission goes only
-- through submit_service_request() (SECURITY DEFINER, validates the
-- caller's own client_id server-side — never a client-supplied client_id).
create policy service_requests_write_by_manager on public.service_requests for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger service_requests_audit_log
  after insert or update on public.service_requests
  for each row
  execute function public.audit_log_from_trigger();

create or replace function public.submit_service_request(
  p_request_type public.service_request_type,
  p_description text,
  p_site_id uuid default null,
  p_contract_id uuid default null,
  p_requested_date date default null,
  p_priority public.task_priority default 'normal'
)
returns public.service_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client_id uuid;
  v_tenant_id uuid;
  v_result public.service_requests;
begin
  select client_id, tenant_id into v_client_id, v_tenant_id from public.client_portal_users where profile_id = auth.uid();
  if v_client_id is null then
    raise exception 'insufficient_privilege: caller has no client portal access';
  end if;

  if p_site_id is not null and not exists (select 1 from public.sites where id = p_site_id and client_id = v_client_id) then
    raise exception 'invalid_reference: site % does not belong to your organisation', p_site_id;
  end if;
  if p_contract_id is not null and not exists (select 1 from public.contracts where id = p_contract_id and client_id = v_client_id) then
    raise exception 'invalid_reference: contract % does not belong to your organisation', p_contract_id;
  end if;

  insert into public.service_requests (tenant_id, client_id, site_id, contract_id, requested_by, request_type, description, requested_date, priority, origin)
  values (v_tenant_id, v_client_id, p_site_id, p_contract_id, auth.uid(), p_request_type, p_description, p_requested_date, p_priority, 'client')
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'service_request_submitted', 'service_requests', v_result.id, null, jsonb_build_object('client_id', v_client_id));

  return v_result;
end;
$$;

comment on function public.submit_service_request(public.service_request_type, text, uuid, uuid, date, public.task_priority) is
  'The only path a client_user can create a service_requests row. client_id/tenant_id are always server-derived from client_portal_users, never client-supplied — a malicious client cannot submit a request against another tenant''s or another client''s site by changing an id.';

revoke execute on function public.submit_service_request(public.service_request_type, text, uuid, uuid, date, public.task_priority) from public, anon;
grant execute on function public.submit_service_request(public.service_request_type, text, uuid, uuid, date, public.task_priority) to authenticated;

-- ---------------------------------------------------------------------------
create table public.variation_orders (
  id                 uuid primary key default gen_random_uuid(),
  tenant_id          uuid not null references public.organizations (id) on delete cascade,
  service_request_id uuid references public.service_requests (id) on delete set null,
  client_id          uuid not null references public.clients (id) on delete cascade,
  contract_id        uuid not null references public.contracts (id) on delete cascade,
  site_id            uuid not null references public.sites (id) on delete cascade,
  title              text not null check (char_length(title) > 0),
  description        text,
  reason             text,
  status             public.variation_order_status not null default 'draft',
  quote_id           uuid references public.quotes (id) on delete set null,
  approved_by        uuid references public.profiles (id) on delete set null,
  approved_at        timestamptz,
  task_id            uuid references public.tasks (id) on delete set null,
  created_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  completed_at       timestamptz
);

comment on table public.variation_orders is
  'Billable work outside a contract''s existing scope. quote_id/task_id point at real rows in the existing quotes/tasks tables — never a duplicate pricing or work-assignment system. client_id is denormalized from contract_id (validated by trigger) so client-facing RLS never needs a join, the same pattern incident_affected_employees already uses to avoid RLS recursion.';

create index variation_orders_tenant_id_idx on public.variation_orders (tenant_id);
create index variation_orders_client_id_idx on public.variation_orders (client_id);
create index variation_orders_contract_id_idx on public.variation_orders (contract_id);
create index variation_orders_status_idx on public.variation_orders (status);

create trigger variation_orders_set_updated_at
  before update on public.variation_orders
  for each row
  execute function public.set_updated_at();

create or replace function public.validate_variation_order_tenant_refs()
returns trigger
language plpgsql
as $$
declare
  v_contract_client_id uuid;
begin
  select client_id into v_contract_client_id from public.contracts where id = new.contract_id and tenant_id = new.tenant_id;
  if v_contract_client_id is null then
    raise exception 'cross_tenant_reference: contract % does not belong to tenant %', new.contract_id, new.tenant_id;
  end if;
  if new.client_id <> v_contract_client_id then
    raise exception 'invalid_reference: client_id % does not match contract %''s client %', new.client_id, new.contract_id, v_contract_client_id;
  end if;
  if not exists (select 1 from public.sites where id = new.site_id and tenant_id = new.tenant_id and client_id = new.client_id) then
    raise exception 'invalid_reference: site % does not belong to client %', new.site_id, new.client_id;
  end if;
  if new.quote_id is not null and not exists (select 1 from public.quotes where id = new.quote_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: quote % does not belong to tenant %', new.quote_id, new.tenant_id;
  end if;
  if new.task_id is not null and not exists (select 1 from public.tasks where id = new.task_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: task % does not belong to tenant %', new.task_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger variation_orders_validate_tenant_refs
  before insert or update on public.variation_orders
  for each row
  execute function public.validate_variation_order_tenant_refs();

create or replace function public.variation_orders_validate_transition()
returns trigger
language plpgsql
as $$
declare
  v_task_status public.task_status;
begin
  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'draft' and new.status in ('assessed', 'cancelled'))
    or (old.status = 'assessed' and new.status in ('quoting', 'cancelled'))
    or (old.status = 'quoting' and new.status in ('quoted', 'cancelled'))
    or (old.status = 'quoted' and new.status in ('approved', 'rejected', 'cancelled'))
    or (old.status = 'approved' and new.status in ('scheduled', 'cancelled'))
    or (old.status = 'scheduled' and new.status in ('in_progress', 'cancelled'))
    or (old.status = 'in_progress' and new.status in ('completed', 'cancelled'))
    or (old.status = 'completed' and new.status = 'invoiced')
  ) then
    raise exception 'invalid_transition: cannot move variation order from % to %', old.status, new.status;
  end if;

  -- A variation with a linked work order cannot be marked completed until
  -- that task itself is genuinely done — never a UI-only completion.
  if new.status = 'completed' and old.task_id is not null then
    select status into v_task_status from public.tasks where id = old.task_id;
    if v_task_status not in ('completed', 'verified') then
      raise exception 'work_not_done: linked task % is not completed (status: %)', old.task_id, v_task_status;
    end if;
    new.completed_at := now();
  end if;

  return new;
end;
$$;

create trigger variation_orders_validate_transition_trigger
  before update on public.variation_orders
  for each row
  execute function public.variation_orders_validate_transition();

alter table public.variation_orders enable row level security;
alter table public.variation_orders force row level security;

create policy variation_orders_select on public.variation_orders for select to authenticated
  using (
    (tenant_id = public.current_tenant_id() and public.can_manage_operations(tenant_id))
    or client_id = public.current_client_id()
    or public.is_platform_admin()
  );

create policy variation_orders_write_by_manager on public.variation_orders for all to authenticated
  using (public.can_manage_operations(tenant_id))
  with check (public.can_manage_operations(tenant_id));

create trigger variation_orders_audit_log
  after insert or update on public.variation_orders
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
create or replace function public.assess_service_request(
  p_request_id uuid,
  p_title text,
  p_description text default null,
  p_reason text default null
)
returns public.variation_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.service_requests;
  v_result public.variation_orders;
begin
  select * into v_request from public.service_requests where id = p_request_id;
  if not found then
    raise exception 'not_found: no service request %', p_request_id;
  end if;

  if not public.can_manage_operations(v_request.tenant_id) then
    raise exception 'insufficient_privilege: cannot assess this request';
  end if;

  if v_request.status not in ('requested') then
    raise exception 'invalid_state: request % is not in a state that can be assessed (status: %)', p_request_id, v_request.status;
  end if;
  if v_request.contract_id is null or v_request.site_id is null then
    raise exception 'missing_contract_or_site: a request needs a contract and site before it can become a variation';
  end if;

  insert into public.variation_orders (tenant_id, service_request_id, client_id, contract_id, site_id, title, description, reason, status, created_by)
  values (v_request.tenant_id, v_request.id, v_request.client_id, v_request.contract_id, v_request.site_id, p_title, coalesce(p_description, v_request.description), p_reason, 'assessed', auth.uid())
  returning * into v_result;

  update public.service_requests set status = 'converted', resolved_at = now() where id = p_request_id;

  perform public.write_audit_log(v_request.tenant_id, auth.uid(), 'service_request_assessed', 'service_requests', p_request_id, null, jsonb_build_object('variation_order_id', v_result.id));

  return v_result;
end;
$$;

revoke execute on function public.assess_service_request(uuid, text, text, text) from public, anon;
grant execute on function public.assess_service_request(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- link_variation_quote: attaches an existing quotes row (created the normal
-- way via the existing quote engine, scoped to the variation's client/site)
-- to a variation, moving it assessed -> quoting.

create or replace function public.link_variation_quote(p_variation_id uuid, p_quote_id uuid)
returns public.variation_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variation public.variation_orders;
  v_quote public.quotes;
  v_result public.variation_orders;
begin
  select * into v_variation from public.variation_orders where id = p_variation_id;
  if not found then
    raise exception 'not_found: no variation order %', p_variation_id;
  end if;
  if not public.can_manage_operations(v_variation.tenant_id) then
    raise exception 'insufficient_privilege: cannot link a quote to this variation';
  end if;
  if v_variation.status <> 'assessed' then
    raise exception 'invalid_state: variation % is not awaiting a quote (status: %)', p_variation_id, v_variation.status;
  end if;

  select * into v_quote from public.quotes where id = p_quote_id and tenant_id = v_variation.tenant_id and client_id = v_variation.client_id;
  if not found then
    raise exception 'invalid_reference: quote % does not belong to this variation''s client', p_quote_id;
  end if;

  update public.variation_orders set quote_id = p_quote_id, status = 'quoting' where id = p_variation_id returning * into v_result;
  return v_result;
end;
$$;

revoke execute on function public.link_variation_quote(uuid, uuid) from public, anon;
grant execute on function public.link_variation_quote(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- mark_variation_quoted: internal action once the linked quote has been
-- sent to the client (quotes.status moved to 'sent'/'viewed' via the
-- existing quote engine) — moves the variation quoting -> quoted so the
-- client portal knows to expect a decision request.

create or replace function public.mark_variation_quoted(p_variation_id uuid)
returns public.variation_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variation public.variation_orders;
  v_result public.variation_orders;
begin
  select * into v_variation from public.variation_orders where id = p_variation_id;
  if not found then
    raise exception 'not_found: no variation order %', p_variation_id;
  end if;
  if not public.can_manage_operations(v_variation.tenant_id) then
    raise exception 'insufficient_privilege: cannot update this variation';
  end if;
  if v_variation.status <> 'quoting' or v_variation.quote_id is null then
    raise exception 'invalid_state: variation % has no quote in progress (status: %)', p_variation_id, v_variation.status;
  end if;

  update public.variation_orders set status = 'quoted' where id = p_variation_id returning * into v_result;
  return v_result;
end;
$$;

revoke execute on function public.mark_variation_quoted(uuid) from public, anon;
grant execute on function public.mark_variation_quoted(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- client_decide_variation: the client-authority boundary. Only the client
-- who owns this variation (via client_portal_users, never a client-supplied
-- id) may approve/reject, only while quoted, exactly once — reuses the
-- existing quotes_validate_transition guard by driving the underlying
-- quote's own status, never duplicating quote-approval logic.

create or replace function public.client_decide_variation(p_variation_id uuid, p_approve boolean)
returns public.variation_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variation public.variation_orders;
  v_caller_client_id uuid;
  v_result public.variation_orders;
begin
  select client_id into v_caller_client_id from public.client_portal_users where profile_id = auth.uid();
  if v_caller_client_id is null then
    raise exception 'insufficient_privilege: caller has no client portal access';
  end if;

  select * into v_variation from public.variation_orders where id = p_variation_id;
  if not found then
    raise exception 'not_found: no variation order %', p_variation_id;
  end if;

  if v_variation.client_id <> v_caller_client_id then
    raise exception 'insufficient_privilege: this variation does not belong to your organisation';
  end if;
  if v_variation.status <> 'quoted' then
    raise exception 'invalid_state: variation % is not awaiting your decision (status: %)', p_variation_id, v_variation.status;
  end if;

  update public.quotes set status = (case when p_approve then 'approved' else 'rejected' end)::public.quote_status where id = v_variation.quote_id;

  update public.variation_orders
    set status = (case when p_approve then 'approved' else 'rejected' end)::public.variation_order_status,
        approved_by = case when p_approve then auth.uid() else approved_by end,
        approved_at = case when p_approve then now() else approved_at end
    where id = p_variation_id
    returning * into v_result;

  perform public.write_audit_log(v_variation.tenant_id, auth.uid(), case when p_approve then 'variation_approved_by_client' else 'variation_rejected_by_client' end, 'variation_orders', p_variation_id, null, null);

  return v_result;
end;
$$;

comment on function public.client_decide_variation(uuid, boolean) is
  'The only path a client can approve/reject a variation. client_id is always server-derived, never client-supplied — a malicious client cannot approve another client''s (or another tenant''s) variation by changing an id. Rejects a non-quoted variation and a caller whose own client_id does not match.';

revoke execute on function public.client_decide_variation(uuid, boolean) from public, anon;
grant execute on function public.client_decide_variation(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- schedule_variation_work: creates the real work order (a `tasks` row —
-- the existing task system, never a duplicate) once a variation is
-- approved.

create or replace function public.schedule_variation_work(
  p_variation_id uuid,
  p_assignee_id uuid default null,
  p_due_at timestamptz default null
)
returns public.variation_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variation public.variation_orders;
  v_task public.tasks;
  v_result public.variation_orders;
begin
  select * into v_variation from public.variation_orders where id = p_variation_id;
  if not found then
    raise exception 'not_found: no variation order %', p_variation_id;
  end if;
  if not public.can_manage_operations(v_variation.tenant_id) then
    raise exception 'insufficient_privilege: cannot schedule this variation';
  end if;
  if v_variation.status <> 'approved' then
    raise exception 'invalid_state: variation % is not approved (status: %)', p_variation_id, v_variation.status;
  end if;

  insert into public.tasks (tenant_id, site_id, assignee_id, title, description, priority, due_at, created_by)
  values (v_variation.tenant_id, v_variation.site_id, p_assignee_id, v_variation.title, v_variation.description, 'normal', p_due_at, auth.uid())
  returning * into v_task;

  update public.variation_orders set task_id = v_task.id, status = 'scheduled' where id = p_variation_id returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.schedule_variation_work(uuid, uuid, timestamptz) from public, anon;
grant execute on function public.schedule_variation_work(uuid, uuid, timestamptz) to authenticated;

-- ---------------------------------------------------------------------------
-- transition_variation_status: the generic internal state-change entry
-- point for the remaining internal-only transitions (scheduled ->
-- in_progress, in_progress -> completed, any -> cancelled). completed is
-- also guarded inside variation_orders_validate_transition() against the
-- linked task's real status — belt and braces, not just this RPC's check.

create or replace function public.transition_variation_status(p_variation_id uuid, p_new_status public.variation_order_status)
returns public.variation_orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_variation public.variation_orders;
  v_result public.variation_orders;
begin
  select * into v_variation from public.variation_orders where id = p_variation_id;
  if not found then
    raise exception 'not_found: no variation order %', p_variation_id;
  end if;
  if not public.can_manage_operations(v_variation.tenant_id) then
    raise exception 'insufficient_privilege: cannot update this variation';
  end if;

  update public.variation_orders set status = p_new_status where id = p_variation_id returning * into v_result;
  return v_result;
end;
$$;

revoke execute on function public.transition_variation_status(uuid, public.variation_order_status) from public, anon;
grant execute on function public.transition_variation_status(uuid, public.variation_order_status) to authenticated;
