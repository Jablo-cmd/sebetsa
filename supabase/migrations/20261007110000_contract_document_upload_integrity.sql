-- Contract documents: a failed storage upload must not leave a phantom record.
--
-- create_contract_document_slot() writes the metadata row before the bytes are
-- uploaded. If the upload then fails, the row would sit in the contract's
-- document list pointing at a file that does not exist. The uploader can
-- discard such a slot (only while it is fresh and only if no object was ever
-- stored at that path); the discard is audited. Contract documents remain
-- otherwise append-only: there is still no general DELETE policy.

create or replace function public.cancel_contract_document_upload(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doc public.contract_documents;
begin
  select * into v_doc from public.contract_documents where id = p_document_id for update;
  if not found then
    raise exception 'not_found: no contract document %', p_document_id;
  end if;

  if v_doc.uploaded_by is distinct from auth.uid() then
    raise exception 'insufficient_privilege: only the uploader can cancel an upload';
  end if;
  if not public.can_manage_org_structure(v_doc.tenant_id) then
    raise exception 'insufficient_privilege: cannot manage documents for this contract';
  end if;
  if v_doc.created_at < now() - interval '15 minutes' then
    raise exception 'invalid_transition: this upload can no longer be cancelled';
  end if;
  if exists (select 1 from storage.objects o where o.bucket_id = 'contract-documents' and o.name = v_doc.storage_path) then
    raise exception 'invalid_transition: the file was uploaded, so the document cannot be cancelled';
  end if;

  delete from public.contract_documents where id = p_document_id;

  perform public.write_audit_log(
    v_doc.tenant_id, auth.uid(), 'contract_document_upload_cancelled', 'contract_documents', p_document_id,
    to_jsonb(v_doc), null
  );
end;
$$;

revoke execute on function public.cancel_contract_document_upload(uuid) from public, anon;
grant execute on function public.cancel_contract_document_upload(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Contract ↔ site links.
--
-- 1. contract_sites had no referential integrity beyond the two foreign keys:
--    a manager could link their contract to a site of another tenant (or of a
--    different client). SLA computation reads operational data by site, so a
--    cross-tenant link is an information-exposure path. The link must now stay
--    inside one tenant and one client.
-- 2. The client replaced a contract's sites with a DELETE followed by an
--    INSERT in two requests; a failure in between left the contract with no
--    sites at all. set_contract_sites() does both in one transaction. It is
--    SECURITY INVOKER so the caller's RLS applies exactly as before.

create or replace function public.validate_contract_site_ref()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_contract public.contracts;
  v_site public.sites;
begin
  select * into v_contract from public.contracts where id = new.contract_id;
  select * into v_site from public.sites where id = new.site_id;
  if v_contract.id is null or v_site.id is null then
    raise exception 'not_found: contract or site does not exist or is not visible';
  end if;
  if v_contract.tenant_id <> new.tenant_id or v_site.tenant_id <> new.tenant_id then
    raise exception 'cross_tenant_reference: contract % and site % must belong to tenant %', new.contract_id, new.site_id, new.tenant_id;
  end if;
  if v_site.client_id is distinct from v_contract.client_id then
    raise exception 'invalid_reference: site % does not belong to the contract''s client', new.site_id;
  end if;
  return new;
end;
$$;

drop trigger if exists contract_sites_validate_ref on public.contract_sites;
create trigger contract_sites_validate_ref
  before insert or update on public.contract_sites
  for each row
  execute function public.validate_contract_site_ref();

create or replace function public.set_contract_sites(p_contract_id uuid, p_site_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.contracts where id = p_contract_id;
  if not found then
    raise exception 'not_found: no contract %', p_contract_id;
  end if;

  delete from public.contract_sites
   where contract_id = p_contract_id
     and not (site_id = any (coalesce(p_site_ids, '{}'::uuid[])));

  insert into public.contract_sites (contract_id, site_id, tenant_id)
  select p_contract_id, s, v_tenant_id from unnest(coalesce(p_site_ids, '{}'::uuid[])) as s
  on conflict (contract_id, site_id) do nothing;
end;
$$;

revoke execute on function public.set_contract_sites(uuid, uuid[]) from public, anon;
grant execute on function public.set_contract_sites(uuid, uuid[]) to authenticated;

-- Trigger functions are never called directly.
revoke execute on function public.validate_contract_site_ref() from public, anon, authenticated;
