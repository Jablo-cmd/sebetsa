-- Sebetsa Phase N — Compliance, Safety & Incident Management, migration 2 of 2.
--
-- RPCs following the exact Phase H/M shape: auth check, tenant/permission
-- check via existing can_manage_operations()/can_manage_employees(), row
-- lock before any status-dependent write, server-derived actor/timestamp
-- fields, write_audit_log() call, explicit EXECUTE grants (Phase H lesson:
-- `revoke ... from public` alone is not enough — authenticated/anon are
-- revoked and re-granted explicitly below for every function).

create or replace function public.incidents_generate_reference_number()
returns trigger
language plpgsql
as $$
begin
  if new.reference_number is null then
    new.reference_number := 'INC-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.incidents_reference_seq')::text, 6, '0');
  end if;
  return new;
end;
$$;

create trigger incidents_generate_reference_number_trigger
  before insert on public.incidents
  for each row
  execute function public.incidents_generate_reference_number();

-- ---------------------------------------------------------------------------
create or replace function public.report_incident(
  p_tenant_id                uuid,
  p_category                 public.incident_category,
  p_severity                 public.incident_severity,
  p_occurred_at              timestamptz,
  p_description               text,
  p_site_id                  uuid default null,
  p_contract_id              uuid default null
) returns public.incidents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result public.incidents;
begin
  if p_tenant_id <> public.current_tenant_id() and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot report an incident for another tenant';
  end if;

  insert into public.incidents (
    tenant_id, site_id, contract_id, category, severity, occurred_at, description, reported_by, status
  ) values (
    p_tenant_id, p_site_id, p_contract_id, p_category, p_severity, p_occurred_at, p_description, auth.uid(), 'reported'
  )
  returning * into v_result;

  perform public.write_audit_log(p_tenant_id, auth.uid(), 'incident_reported', 'incidents', v_result.id, null, to_jsonb(v_result));

  if p_severity in ('high', 'critical') then
    perform public.create_notification(
      pr.id, 'incident_reported', 'New ' || p_severity || ' severity incident: ' || v_result.reference_number,
      left(p_description, 200), p_tenant_id, 'incidents', v_result.id, null
    )
    from public.profiles pr
    join auth.users u on u.id = pr.id
    where pr.tenant_id = p_tenant_id
      and coalesce(u.raw_app_meta_data ->> 'role', '') in ('organization_administrator', 'operations_manager');
  end if;

  return v_result;
end;
$$;

revoke execute on function public.report_incident(uuid, public.incident_category, public.incident_severity, timestamptz, text, uuid, uuid) from public, anon;
grant execute on function public.report_incident(uuid, public.incident_category, public.incident_severity, timestamptz, text, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.link_incident_employee(
  p_incident_id  uuid,
  p_employee_id  uuid,
  p_involvement  text default 'involved'
) returns public.incident_affected_employees
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.incident_affected_employees;
begin
  select tenant_id into v_tenant_id from public.incidents where id = p_incident_id;
  if not found then
    raise exception 'not_found: no incident %', p_incident_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot link employees to this incident';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id and tenant_id = v_tenant_id) then
    raise exception 'cross_tenant_reference: employee % does not belong to this tenant', p_employee_id;
  end if;

  insert into public.incident_affected_employees (tenant_id, incident_id, employee_id, involvement)
  values (v_tenant_id, p_incident_id, p_employee_id, p_involvement)
  on conflict (incident_id, employee_id) do update set involvement = excluded.involvement
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'incident_employee_linked', 'incidents', p_incident_id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.link_incident_employee(uuid, uuid, text) from public, anon;
grant execute on function public.link_incident_employee(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.transition_incident_status(
  p_incident_id  uuid,
  p_new_status   public.incident_status,
  p_notes        text default null
) returns public.incidents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_old_status public.incident_status;
  v_result public.incidents;
begin
  select tenant_id, status into v_tenant_id, v_old_status
  from public.incidents where id = p_incident_id
  for update;

  if not found then
    raise exception 'not_found: no incident %', p_incident_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot manage this incident';
  end if;

  update public.incidents
    set status = p_new_status,
        investigation_notes = coalesce(p_notes, investigation_notes),
        closed_by = case when p_new_status = 'closed' then auth.uid() else null end,
        closed_at = case when p_new_status = 'closed' then now() else null end
    where id = p_incident_id
    returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'incident_status_changed', 'incidents', p_incident_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status)
  );

  return v_result;
end;
$$;

revoke execute on function public.transition_incident_status(uuid, public.incident_status, text) from public, anon;
grant execute on function public.transition_incident_status(uuid, public.incident_status, text) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.add_incident_action(
  p_incident_id      uuid,
  p_description      text,
  p_owner_profile_id uuid default null,
  p_due_date         date default null
) returns public.incident_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.incident_actions;
begin
  select tenant_id into v_tenant_id from public.incidents where id = p_incident_id;
  if not found then
    raise exception 'not_found: no incident %', p_incident_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot add actions to this incident';
  end if;

  insert into public.incident_actions (tenant_id, incident_id, description, owner_profile_id, due_date)
  values (v_tenant_id, p_incident_id, p_description, p_owner_profile_id, p_due_date)
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'incident_action_added', 'incident_actions', v_result.id, null, to_jsonb(v_result));

  if p_owner_profile_id is not null then
    perform public.create_notification(
      p_owner_profile_id, 'incident_action_assigned', 'Corrective action assigned',
      p_description, v_tenant_id, 'incident_actions', v_result.id, null
    );
  end if;

  return v_result;
end;
$$;

revoke execute on function public.add_incident_action(uuid, text, uuid, date) from public, anon;
grant execute on function public.add_incident_action(uuid, text, uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.complete_incident_action(p_action_id uuid)
returns public.incident_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_owner_profile_id uuid;
  v_status public.incident_action_status;
  v_result public.incident_actions;
begin
  select tenant_id, owner_profile_id, status into v_tenant_id, v_owner_profile_id, v_status
  from public.incident_actions where id = p_action_id
  for update;

  if not found then
    raise exception 'not_found: no incident action %', p_action_id;
  end if;

  if v_owner_profile_id <> auth.uid() and not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: only the action owner or a manager may complete this action';
  end if;

  if v_status = 'verified' then
    raise exception 'invalid_transition: action already verified, cannot re-complete';
  end if;

  update public.incident_actions
    set status = 'completed', completed_at = now()
    where id = p_action_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'incident_action_completed', 'incident_actions', p_action_id, jsonb_build_object('status', v_status), jsonb_build_object('status', 'completed'));

  return v_result;
end;
$$;

revoke execute on function public.complete_incident_action(uuid) from public, anon;
grant execute on function public.complete_incident_action(uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.verify_incident_action(p_action_id uuid)
returns public.incident_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_status public.incident_action_status;
  v_result public.incident_actions;
begin
  select tenant_id, status into v_tenant_id, v_status
  from public.incident_actions where id = p_action_id
  for update;

  if not found then
    raise exception 'not_found: no incident action %', p_action_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify this action';
  end if;

  if v_status <> 'completed' then
    raise exception 'invalid_transition: action must be completed before it can be verified (currently %)', v_status;
  end if;

  update public.incident_actions
    set status = 'verified', verified_by = auth.uid(), verified_at = now()
    where id = p_action_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'incident_action_verified', 'incident_actions', p_action_id, jsonb_build_object('status', 'completed'), jsonb_build_object('status', 'verified'));

  return v_result;
end;
$$;

revoke execute on function public.verify_incident_action(uuid) from public, anon;
grant execute on function public.verify_incident_action(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Compliance records: upsert covers both create and progress-update; a
-- separate, narrower RPC (verify_compliance_record) is the only path that
-- can mark a record 'compliant' with a server-derived verifier — the
-- responsible person can move it to 'in_progress'/attach evidence, but
-- cannot self-verify their own compliance.

create or replace function public.upsert_compliance_record(
  p_id                      uuid,
  p_requirement_id          uuid,
  p_site_id                 uuid,
  p_client_id               uuid,
  p_contract_id             uuid,
  p_responsible_profile_id  uuid,
  p_due_date                date,
  p_expiry_date             date,
  p_evidence_storage_path   text default null,
  p_notes                   text default null
) returns public.compliance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.compliance_records;
begin
  select tenant_id into v_tenant_id from public.compliance_requirements where id = p_requirement_id;
  if not found then
    raise exception 'not_found: no compliance requirement %', p_requirement_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot manage compliance records for this tenant';
  end if;

  if p_id is null then
    insert into public.compliance_records (
      tenant_id, requirement_id, site_id, client_id, contract_id, responsible_profile_id,
      due_date, expiry_date, evidence_storage_path, notes,
      status
    ) values (
      v_tenant_id, p_requirement_id, p_site_id, p_client_id, p_contract_id, p_responsible_profile_id,
      p_due_date, p_expiry_date, p_evidence_storage_path, p_notes,
      case when p_evidence_storage_path is not null then 'in_progress' else 'pending' end::public.compliance_status
    )
    returning * into v_result;

    perform public.write_audit_log(v_tenant_id, auth.uid(), 'compliance_record_created', 'compliance_records', v_result.id, null, to_jsonb(v_result));
  else
    update public.compliance_records
      set site_id = p_site_id,
          client_id = p_client_id,
          contract_id = p_contract_id,
          responsible_profile_id = p_responsible_profile_id,
          due_date = p_due_date,
          expiry_date = p_expiry_date,
          evidence_storage_path = coalesce(p_evidence_storage_path, evidence_storage_path),
          notes = p_notes,
          status = case
            when status = 'compliant' then status
            when p_evidence_storage_path is not null then 'in_progress'::public.compliance_status
            else status
          end
      where id = p_id and tenant_id = v_tenant_id
      returning * into v_result;

    if not found then
      raise exception 'not_found: no compliance record % for this tenant', p_id;
    end if;

    perform public.write_audit_log(v_tenant_id, auth.uid(), 'compliance_record_updated', 'compliance_records', p_id, null, to_jsonb(v_result));
  end if;

  return v_result;
end;
$$;

revoke execute on function public.upsert_compliance_record(uuid, uuid, uuid, uuid, uuid, uuid, date, date, text, text) from public, anon;
grant execute on function public.upsert_compliance_record(uuid, uuid, uuid, uuid, uuid, uuid, date, date, text, text) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.verify_compliance_record(p_id uuid, p_approve boolean)
returns public.compliance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_old_status public.compliance_status;
  v_result public.compliance_records;
begin
  select tenant_id, status into v_tenant_id, v_old_status
  from public.compliance_records where id = p_id
  for update;

  if not found then
    raise exception 'not_found: no compliance record %', p_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify compliance records for this tenant';
  end if;

  update public.compliance_records
    set status = case when p_approve then 'compliant'::public.compliance_status else 'non_compliant'::public.compliance_status end,
        verified_by = auth.uid(),
        verified_at = now(),
        completed_date = case when p_approve then current_date else completed_date end
    where id = p_id
    returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'compliance_record_verified', 'compliance_records', p_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', v_result.status)
  );

  return v_result;
end;
$$;

revoke execute on function public.verify_compliance_record(uuid, boolean) from public, anon;
grant execute on function public.verify_compliance_record(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Expiry sweep — mirrors sync_expired_documents (Phase M): manually
-- triggered/cron-ready, marks anything past its expiry_date as 'expired'
-- unless already waived, and notifies the responsible person once.

create or replace function public.sync_expired_compliance_records(p_tenant_id uuid)
returns setof public.compliance_records
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record record;
begin
  if not public.can_manage_operations(p_tenant_id) then
    raise exception 'insufficient_privilege: cannot sync compliance records for this tenant';
  end if;

  for v_record in
    update public.compliance_records
    set status = 'expired'
    where tenant_id = p_tenant_id
      and status not in ('expired', 'waived')
      and expiry_date is not null
      and expiry_date < current_date
    returning *
  loop
    if v_record.responsible_profile_id is not null then
      perform public.create_notification(
        v_record.responsible_profile_id, 'compliance_expired', 'Compliance record expired',
        'A compliance record you are responsible for has expired and needs renewal.',
        p_tenant_id, 'compliance_records', v_record.id, null
      );
    end if;

    perform public.write_audit_log(p_tenant_id, auth.uid(), 'compliance_record_expired', 'compliance_records', v_record.id, null, jsonb_build_object('status', 'expired'));

    return next v_record;
  end loop;
end;
$$;

revoke execute on function public.sync_expired_compliance_records(uuid) from public, anon;
grant execute on function public.sync_expired_compliance_records(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Private storage bucket for compliance/incident evidence — reuses the
-- exact employee-documents pattern (Phase M): private bucket, path
-- convention keyed on tenant segment, storage.objects policies re-checking
-- the metadata table rather than trusting the bucket alone. Path
-- convention: {tenant_id}/incidents/{incident_id}/{file_name} or
-- {tenant_id}/compliance/{record_id}/{file_name}.

insert into storage.buckets (id, name, public)
values ('compliance-evidence', 'compliance-evidence', false)
on conflict (id) do nothing;

create policy compliance_evidence_storage_select on storage.objects for select to authenticated
  using (
    bucket_id = 'compliance-evidence'
    and (
      public.can_manage_operations((storage.foldername(name))[1]::uuid)
      or public.is_platform_admin()
    )
  );

create policy compliance_evidence_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'compliance-evidence'
    and (
      public.can_manage_operations((storage.foldername(name))[1]::uuid)
      or public.is_platform_admin()
    )
  );

comment on policy compliance_evidence_storage_select on storage.objects is
  'Evidence is operational (incident/compliance), not employee-personal, so visibility follows can_manage_operations() on the tenant path segment rather than an own-employee carve-out.';
