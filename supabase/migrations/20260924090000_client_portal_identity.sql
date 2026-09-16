-- Sebetsa Phase T — Client Portal Identity.
--
-- The single missing piece every client-facing feature in this sprint
-- depends on: today `client_user` is a role with an empty permission set
-- and no link to WHICH client business entity an authenticated account
-- represents. Without this, "client A must not see client B's data within
-- the same tenant" (the brief's own highest-risk requirement) is
-- structurally impossible to enforce — RLS has nothing to filter on.
--
-- client_portal_users is the link; current_client_id() is the RLS-usable
-- helper every client-facing table's policies key off, mirroring
-- current_tenant_id()'s existing role in every other policy in this
-- codebase. provision_client_portal_login() reuses admin_create_user()
-- (Phase D, 20260911100300) exactly the way
-- provision_employee_login() does — no new auth-user-creation path
-- invented.

create table public.client_portal_users (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.organizations (id) on delete cascade,
  client_id   uuid not null references public.clients (id) on delete cascade,
  profile_id  uuid not null unique references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now()
);

comment on table public.client_portal_users is
  'Links an authenticated client_user profile to the one client business entity they represent. unique(profile_id) — one portal login represents exactly one client; a contact needing access to multiple clients gets multiple logins, the same simplification employees.profile_id already makes for staff.';

create index client_portal_users_tenant_id_idx on public.client_portal_users (tenant_id);
create index client_portal_users_client_id_idx on public.client_portal_users (client_id);

create or replace function public.validate_client_portal_user_tenant_refs()
returns trigger
language plpgsql
as $$
begin
  if not exists (select 1 from public.clients where id = new.client_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: client % does not belong to tenant %', new.client_id, new.tenant_id;
  end if;
  if not exists (select 1 from public.profiles where id = new.profile_id and tenant_id = new.tenant_id) then
    raise exception 'cross_tenant_reference: profile % does not belong to tenant %', new.profile_id, new.tenant_id;
  end if;
  return new;
end;
$$;

create trigger client_portal_users_validate_tenant_refs
  before insert or update on public.client_portal_users
  for each row
  execute function public.validate_client_portal_user_tenant_refs();

alter table public.client_portal_users enable row level security;
alter table public.client_portal_users force row level security;

-- A client_user may read their own link row (to know their own client_id
-- client-side); internal management can read every link in their tenant.
create policy client_portal_users_select on public.client_portal_users for select to authenticated
  using (profile_id = auth.uid() or public.can_manage_org_structure(tenant_id) or public.is_platform_admin());

-- No direct client write policy — provision_client_portal_login() only.

create trigger client_portal_users_audit_log
  after insert on public.client_portal_users
  for each row
  execute function public.audit_log_from_trigger();

-- ---------------------------------------------------------------------------
-- current_client_id(): the RLS-usable "which client is this caller" helper,
-- the client-facing counterpart to current_tenant_id(). Returns null for
-- every non-client_user caller (internal staff, platform admin) — those
-- callers' access is governed by can_manage_org_structure()/
-- can_manage_operations() exactly as today, never by this function.

create or replace function public.current_client_id()
returns uuid
language sql
stable
as $$
  select client_id from public.client_portal_users where profile_id = auth.uid()
$$;

comment on function public.current_client_id() is
  'The client business entity the calling client_user represents, or null for every other role. Client-facing table RLS policies use this alongside current_tenant_id() — never trust a client-supplied client_id.';

grant execute on function public.current_client_id() to authenticated;

-- ---------------------------------------------------------------------------
-- provision_client_portal_login: reuses admin_create_user() exactly as
-- provision_employee_login() does for staff — no second user-creation path.

create or replace function public.provision_client_portal_login(
  p_client_id uuid,
  p_email text,
  p_first_name text,
  p_last_name text,
  p_phone text default null
)
returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant_id uuid;
  v_result record;
begin
  select tenant_id into v_tenant_id from public.clients where id = p_client_id;
  if not found then
    raise exception 'not_found: no client %', p_client_id;
  end if;

  if not public.can_manage_org_structure(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot provision client portal access for this organization';
  end if;

  select * into v_result from public.admin_create_user(p_email, p_first_name, p_last_name, p_phone, 'client_user', v_tenant_id);

  insert into public.client_portal_users (tenant_id, client_id, profile_id)
  values (v_tenant_id, p_client_id, v_result.user_id);

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'client_portal_login_provisioned', 'clients', p_client_id,
    null, jsonb_build_object('profile_id', v_result.user_id)
  );

  return query select v_result.user_id, v_result.temporary_password;
end;
$$;

comment on function public.provision_client_portal_login(uuid, text, text, text, text) is
  'The one path that gives a client business entity portal access — same admin_create_user() atomic auth-user-creation reused by provision_employee_login(), just linked via client_portal_users instead of employees.profile_id.';

revoke execute on function public.provision_client_portal_login(uuid, text, text, text, text) from public, anon;
grant execute on function public.provision_client_portal_login(uuid, text, text, text, text) to authenticated;
