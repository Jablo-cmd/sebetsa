-- Sebetsa Phase P — Client, Contract & SLA Management, migration 3 of 3.
--
-- compute_sla_measurement() is the only place an SLA number is ever
-- produced — every metric is a real aggregate over Sebetsa's own
-- operational tables (shifts/attendance_records, tasks, incidents,
-- compliance_records), computed at call time. No metric is ever
-- fabricated, hard-coded, or accepted as a client-supplied value.

create or replace function public.compute_sla_measurement(
  p_sla_definition_id uuid,
  p_period_start      date,
  p_period_end        date
) returns public.sla_measurements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_contract_id uuid;
  v_site_id uuid;
  v_metric_type public.sla_metric_type;
  v_target numeric;
  v_operator text;
  v_measured numeric;
  v_target_met boolean;
  v_result public.sla_measurements;
begin
  select tenant_id, contract_id, site_id, metric_type, target_value, threshold_operator
    into v_tenant_id, v_contract_id, v_site_id, v_metric_type, v_target, v_operator
  from public.sla_definitions where id = p_sla_definition_id;

  if not found then
    raise exception 'not_found: no SLA definition %', p_sla_definition_id;
  end if;

  if not public.can_manage_operations(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot compute SLA measurements for this tenant';
  end if;

  if v_site_id is null then
    raise exception 'invalid_configuration: this SLA definition has no site to measure against';
  end if;

  if p_period_end < p_period_start then
    raise exception 'invalid_period: period_end must not be before period_start';
  end if;

  if v_metric_type = 'staffing_fulfillment' then
    select coalesce(
      100.0 * count(*) filter (where ar.status in ('present', 'late')) / nullif(count(*), 0),
      0
    )
    into v_measured
    from public.shifts s
    left join public.attendance_records ar on ar.shift_id = s.id
    where s.site_id = v_site_id
      and s.starts_at::date between p_period_start and p_period_end;

  elsif v_metric_type = 'task_completion_rate' then
    select coalesce(
      100.0 * count(*) filter (where t.status in ('completed', 'verified')) / nullif(count(*), 0),
      0
    )
    into v_measured
    from public.tasks t
    where t.site_id = v_site_id
      and t.due_at is not null
      and t.due_at::date between p_period_start and p_period_end;

  elsif v_metric_type = 'incident_response_hours' then
    select coalesce(avg(extract(epoch from (i.closed_at - i.created_at)) / 3600.0), 0)
    into v_measured
    from public.incidents i
    where i.site_id = v_site_id
      and i.status = 'closed'
      and i.closed_at is not null
      and i.closed_at::date between p_period_start and p_period_end;

  elsif v_metric_type = 'compliance_completion_rate' then
    select coalesce(
      100.0 * count(*) filter (where cr.status = 'compliant') / nullif(count(*), 0),
      0
    )
    into v_measured
    from public.compliance_records cr
    where cr.site_id = v_site_id
      and cr.due_date is not null
      and cr.due_date between p_period_start and p_period_end;

  else
    raise exception 'invalid_configuration: unhandled metric_type %', v_metric_type;
  end if;

  v_target_met := case when v_operator = 'gte' then v_measured >= v_target else v_measured <= v_target end;

  insert into public.sla_measurements (tenant_id, sla_definition_id, period_start, period_end, measured_value, target_met, computed_by)
  values (v_tenant_id, p_sla_definition_id, p_period_start, p_period_end, v_measured, v_target_met, auth.uid())
  returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'sla_measurement_computed', 'sla_measurements', v_result.id, null, to_jsonb(v_result)
  );

  return v_result;
end;
$$;

revoke execute on function public.compute_sla_measurement(uuid, date, date) from public, anon;
grant execute on function public.compute_sla_measurement(uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Contract document upload slot — mirrors create_document_upload_slot
-- (Phase M): the metadata row is created first, under server control, so
-- the client never chooses its own storage_path or version.

create or replace function public.create_contract_document_slot(
  p_contract_id     uuid,
  p_file_name       text,
  p_mime_type       text,
  p_file_size_bytes integer
) returns public.contract_documents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_next_version integer;
  v_storage_path text;
  v_result public.contract_documents;
begin
  select tenant_id into v_tenant_id from public.contracts where id = p_contract_id;
  if not found then
    raise exception 'not_found: no contract %', p_contract_id;
  end if;

  if not public.can_manage_org_structure(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot upload documents for this contract';
  end if;

  select coalesce(max(version), 0) + 1 into v_next_version from public.contract_documents where contract_id = p_contract_id;
  v_storage_path := v_tenant_id::text || '/' || p_contract_id::text || '/' || gen_random_uuid()::text || '-' || p_file_name;

  insert into public.contract_documents (tenant_id, contract_id, file_name, mime_type, file_size_bytes, storage_path, version, uploaded_by)
  values (v_tenant_id, p_contract_id, p_file_name, p_mime_type, p_file_size_bytes, v_storage_path, v_next_version, auth.uid())
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'contract_document_uploaded', 'contract_documents', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.create_contract_document_slot(uuid, text, text, integer) from public, anon;
grant execute on function public.create_contract_document_slot(uuid, text, text, integer) to authenticated;
