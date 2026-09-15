-- Sebetsa — P1 remediation (docs/SEBETSA_REMEDIATION_REPORT.md "Remaining
-- Risks" #1): verify_employee_qualification/verify_employee_skill were
-- named in the original audit's HIGH self-approval finding but omitted
-- from the prior remediation pass's five-RPC guard sweep. Closing that gap
-- here, using decide_procurement_request()'s already-proven pattern —
-- same as every other guard added in 20260919090400_p0_self_approval_guards.sql.
--
-- Unlike leave/attendance/task/compliance/incident, the "subject" here is
-- not the employees row directly reachable from the target table (there is
-- no employee_id column with a direct FK the verifier's own row could
-- match) — employee_skills/employee_qualifications both carry
-- employee_id, and the subject is identified the same way
-- 20260919090400 identified it for compliance/incident ("responsible
-- person"/"owner"): join employees on employee_id and compare
-- employees.profile_id to auth.uid(). platform_administrator is
-- deliberately exempted, matching every other guard in this codebase.

create or replace function public.verify_employee_skill(p_employee_skill_id uuid)
returns public.employee_skills
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_self boolean;
  v_result public.employee_skills;
begin
  select es.tenant_id, (e.profile_id = auth.uid())
    into v_tenant_id, v_is_self
  from public.employee_skills es
  join public.employees e on e.id = es.employee_id
  where es.id = p_employee_skill_id
  for update;

  if not found then
    raise exception 'not_found: no employee skill %', p_employee_skill_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify skills for this tenant';
  end if;

  if v_is_self and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot verify your own skill';
  end if;

  update public.employee_skills set verified_by = auth.uid(), verified_at = now() where id = p_employee_skill_id returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'employee_skill_verified', 'employee_skills', p_employee_skill_id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.verify_employee_skill(uuid) from public, anon;
grant execute on function public.verify_employee_skill(uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.verify_employee_qualification(p_id uuid, p_approve boolean)
returns public.employee_qualifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_self boolean;
  v_result public.employee_qualifications;
begin
  select eq.tenant_id, (e.profile_id = auth.uid())
    into v_tenant_id, v_is_self
  from public.employee_qualifications eq
  join public.employees e on e.id = eq.employee_id
  where eq.id = p_id
  for update;

  if not found then
    raise exception 'not_found: no qualification %', p_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify qualifications for this tenant';
  end if;

  if v_is_self and not public.is_platform_admin() then
    raise exception 'insufficient_privilege: cannot verify your own qualification';
  end if;

  update public.employee_qualifications
    set status = case when p_approve then 'verified'::public.credential_status else 'revoked'::public.credential_status end,
        verified_by = auth.uid(), verified_at = now()
    where id = p_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'employee_qualification_verified', 'employee_qualifications', p_id, null, jsonb_build_object('status', v_result.status));

  return v_result;
end;
$$;

revoke execute on function public.verify_employee_qualification(uuid, boolean) from public, anon;
grant execute on function public.verify_employee_qualification(uuid, boolean) to authenticated;
