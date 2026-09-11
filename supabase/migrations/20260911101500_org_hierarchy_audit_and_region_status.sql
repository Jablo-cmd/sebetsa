-- Sebetsa Phase E — Organisation Hierarchy: audit trail + region status
--
-- 1. regions had no status column — every other org-hierarchy entity
--    (clients, sites) already carries entity_status, and the brief calls
--    for "deactivate/archive region where supported by schema/design". The
--    schema wasn't sufficient, so it's extended here rather than worked
--    around in the UI.
--
-- 2. regions/clients/sites/contracts are plain RLS-gated table writes (no
--    RPC front door), the same shape Funda360's audit_log_from_trigger()
--    was built for (see its own migration comment) — that generic trigger
--    body doesn't exist yet in Sebetsa (only the explicit write_audit_log()
--    RPC insertion point was carried over). Added here and attached to
--    exactly these four tables by name — a deliberate allowlist, not a
--    blanket every-table trigger.

alter table public.regions add column status public.entity_status not null default 'active';

-- ---------------------------------------------------------------------------
create or replace function public.audit_log_from_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_entity_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  if tg_op = 'DELETE' then
    v_tenant_id := old.tenant_id;
    v_entity_id := old.id;
    v_before := to_jsonb(old);
    v_after := null;
  else
    v_tenant_id := new.tenant_id;
    v_entity_id := new.id;
    v_after := to_jsonb(new);
    v_before := case when tg_op = 'UPDATE' then to_jsonb(old) else null end;
  end if;

  insert into public.audit_log (tenant_id, actor_profile_id, action, entity_table, entity_id, before, after)
  values (v_tenant_id, auth.uid(), lower(tg_op) || '_' || tg_table_name, tg_table_name, v_entity_id, v_before, v_after);

  return null; -- AFTER trigger — return value is ignored either way.
end;
$$;

comment on function public.audit_log_from_trigger() is
  'Generic AFTER INSERT/UPDATE/DELETE trigger body — attached only to tables explicitly listed in this migration (an allowlist), not applied blanket-wide. auth.uid() is correct here (unlike write_audit_log''s explicit p_actor_profile_id parameter) because a trigger fires inside the calling client''s own request, which does carry a JWT.';

create trigger regions_audit_log
  after insert or update on public.regions
  for each row
  execute function public.audit_log_from_trigger();

create trigger clients_audit_log
  after insert or update on public.clients
  for each row
  execute function public.audit_log_from_trigger();

create trigger sites_audit_log
  after insert or update on public.sites
  for each row
  execute function public.audit_log_from_trigger();

create trigger contracts_audit_log
  after insert or update on public.contracts
  for each row
  execute function public.audit_log_from_trigger();
