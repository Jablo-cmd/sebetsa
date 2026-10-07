-- Contract document upload integrity: cancel_contract_document_upload().

begin;

insert into public.organizations (id, name, status) values
  ('00000000-0000-0000-0000-0000000f0401', 'Org I', 'active');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', u.id::uuid, 'authenticated', 'authenticated', u.email, crypt('x', gen_salt('bf')), now(),
       jsonb_build_object('role', u.role), '{}', now(), now()
from (values
  ('00000000-0000-0000-0000-0000000f0411', 'admin-i@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0412', 'ops-i@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0413', 'employee-i@example.com', 'employee')
) as u(id, email, role);

insert into public.profiles (id, tenant_id, first_name, last_name, email, role, status)
select p.id::uuid, '00000000-0000-0000-0000-0000000f0401', p.fname, 'I', p.email, p.role::public.user_role, 'active'
from (values
  ('00000000-0000-0000-0000-0000000f0411', 'Admin', 'admin-i@example.com', 'organization_administrator'),
  ('00000000-0000-0000-0000-0000000f0412', 'Ops', 'ops-i@example.com', 'operations_manager'),
  ('00000000-0000-0000-0000-0000000f0413', 'Emp', 'employee-i@example.com', 'employee')
) as p(id, fname, email, role);

insert into public.clients (id, tenant_id, name) values ('00000000-0000-0000-0000-0000000f0421', '00000000-0000-0000-0000-0000000f0401', 'Client I');
insert into public.contracts (id, tenant_id, client_id, contract_number, start_date, status) values
  ('00000000-0000-0000-0000-0000000f0431', '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0421', 'CTR-I', current_date, 'active');

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0411","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_doc public.contract_documents; v_count int; v_audit int;
begin
  -- A slot whose file never reached storage can be discarded by its uploader.
  select * into v_doc from public.create_contract_document_slot('00000000-0000-0000-0000-0000000f0431', 'terms.pdf', 'application/pdf', 1000);

  begin
    perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0412","app_metadata":{"role":"operations_manager"}}', true);
    perform public.cancel_contract_document_upload(v_doc.id);
    raise exception 'SECURITY_FAILURE: someone other than the uploader cancelled a contract document upload';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'insufficient_privilege%' then raise exception 'FAIL: expected insufficient_privilege, got %', sqlerrm; end if;
  end;

  perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0411","app_metadata":{"role":"organization_administrator"}}', true);
  perform public.cancel_contract_document_upload(v_doc.id);
  select count(*) into v_count from public.contract_documents where id = v_doc.id;
  if v_count <> 0 then raise exception 'FAIL: cancelled contract document still present'; end if;

  reset role;
  select count(*) into v_audit from public.audit_log where entity_table = 'contract_documents' and entity_id = v_doc.id and action = 'contract_document_upload_cancelled';
  if v_audit <> 1 then raise exception 'FAIL: expected one cancellation audit event, got %', v_audit; end if;
  raise notice 'PASS: only the uploader can discard an unstored contract document slot, and it is audited';
end $$;

reset role;
reset request.jwt.claims;
do $$
declare v_doc public.contract_documents;
begin
  -- Once the file exists in storage the record can no longer be cancelled.
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0411","app_metadata":{"role":"organization_administrator"}}', true);
  select * into v_doc from public.create_contract_document_slot('00000000-0000-0000-0000-0000000f0431', 'signed.pdf', 'application/pdf', 1000);
  reset role;
  insert into storage.buckets (id, name, public) values ('contract-documents', 'contract-documents', false) on conflict (id) do nothing;
  insert into storage.objects (bucket_id, name) values ('contract-documents', v_doc.storage_path);

  set local role authenticated;
  begin
    perform public.cancel_contract_document_upload(v_doc.id);
    raise exception 'SECURITY_FAILURE: a stored contract document was cancelled';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'invalid_transition%' then raise exception 'FAIL: expected invalid_transition, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: a contract document whose file was stored cannot be cancelled';
end $$;


-- ---------------------------------------------------------------------------
-- Contract <-> site links stay inside one tenant and one client, and a
-- failing replacement leaves the existing links untouched.
-- ---------------------------------------------------------------------------
reset role;
reset request.jwt.claims;
insert into public.organizations (id, name, status) values ('00000000-0000-0000-0000-0000000f0402', 'Org J', 'active');
insert into public.clients (id, tenant_id, name) values
  ('00000000-0000-0000-0000-0000000f0422', '00000000-0000-0000-0000-0000000f0401', 'Other client I'),
  ('00000000-0000-0000-0000-0000000f0423', '00000000-0000-0000-0000-0000000f0402', 'Client J');
insert into public.sites (id, tenant_id, client_id, name) values
  ('00000000-0000-0000-0000-0000000f0441', '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0421', 'Site I1'),
  ('00000000-0000-0000-0000-0000000f0442', '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0421', 'Site I2'),
  ('00000000-0000-0000-0000-0000000f0443', '00000000-0000-0000-0000-0000000f0401', '00000000-0000-0000-0000-0000000f0422', 'Site of another client'),
  ('00000000-0000-0000-0000-0000000f0444', '00000000-0000-0000-0000-0000000f0402', '00000000-0000-0000-0000-0000000f0423', 'Site of another tenant');

set local role authenticated;
set local request.jwt.claims = '{"aal":"aal2","sub":"00000000-0000-0000-0000-0000000f0411","app_metadata":{"role":"organization_administrator"}}';

do $$
declare v_sites uuid[];
begin
  perform public.set_contract_sites('00000000-0000-0000-0000-0000000f0431', array['00000000-0000-0000-0000-0000000f0441','00000000-0000-0000-0000-0000000f0442']::uuid[]);
  select array_agg(site_id order by site_id) into v_sites from public.contract_sites where contract_id = '00000000-0000-0000-0000-0000000f0431';
  if cardinality(v_sites) <> 2 then raise exception 'FAIL: expected 2 linked sites, got %', v_sites; end if;

  perform public.set_contract_sites('00000000-0000-0000-0000-0000000f0431', array['00000000-0000-0000-0000-0000000f0442']::uuid[]);
  select array_agg(site_id) into v_sites from public.contract_sites where contract_id = '00000000-0000-0000-0000-0000000f0431';
  if v_sites <> array['00000000-0000-0000-0000-0000000f0442']::uuid[] then raise exception 'FAIL: replacement did not keep exactly the requested site: %', v_sites; end if;

  begin
    perform public.set_contract_sites('00000000-0000-0000-0000-0000000f0431', array['00000000-0000-0000-0000-0000000f0441','00000000-0000-0000-0000-0000000f0443']::uuid[]);
    raise exception 'SECURITY_FAILURE: a site of a different client was linked to the contract';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'invalid_reference%' then raise exception 'FAIL: expected invalid_reference, got %', sqlerrm; end if;
  end;
  -- The failed call must have rolled back entirely: the previous link survives.
  select array_agg(site_id) into v_sites from public.contract_sites where contract_id = '00000000-0000-0000-0000-0000000f0431';
  if v_sites <> array['00000000-0000-0000-0000-0000000f0442']::uuid[] then raise exception 'FAIL: a rejected replacement changed the existing links: %', v_sites; end if;

  begin
    insert into public.contract_sites (contract_id, site_id, tenant_id) values ('00000000-0000-0000-0000-0000000f0431', '00000000-0000-0000-0000-0000000f0444', '00000000-0000-0000-0000-0000000f0401');
    raise exception 'SECURITY_FAILURE: a site of another tenant was linked to the contract';
  exception when others then
    if sqlerrm like 'SECURITY_FAILURE%' then raise; end if;
    if sqlerrm not like 'cross_tenant_reference%' and sqlerrm not like 'not_found%' then raise exception 'FAIL: expected a reference error, got %', sqlerrm; end if;
  end;
  raise notice 'PASS: contract-site links are tenant- and client-bound, and replacement is atomic';
end $$;

rollback;
