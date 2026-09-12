-- Sebetsa Phase Q — Workforce Performance, Training & Skills, migration 2 of 2.
--
-- RPCs follow the exact Phase H/M/N/O/P shape: auth check, permission
-- check via can_manage_employees(), row lock before status-dependent
-- writes, server-derived actor/timestamp fields, write_audit_log() call,
-- explicit EXECUTE grants (revoke from public/anon, grant to authenticated
-- only — the Phase H lesson).

-- ---------------------------------------------------------------------------
-- Skills: self or manager can record proficiency; only a manager verifies.

create or replace function public.set_employee_skill(
  p_employee_id       uuid,
  p_skill_id          uuid,
  p_proficiency_level public.proficiency_level
) returns public.employee_skills
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_is_self boolean;
  v_result public.employee_skills;
begin
  select tenant_id, (profile_id = auth.uid()) into v_tenant_id, v_is_self from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not (v_is_self or public.can_manage_employees(v_tenant_id)) then
    raise exception 'insufficient_privilege: cannot set skills for this employee';
  end if;

  insert into public.employee_skills (tenant_id, employee_id, skill_id, proficiency_level)
  values (v_tenant_id, p_employee_id, p_skill_id, p_proficiency_level)
  on conflict (employee_id, skill_id) do update
    set proficiency_level = excluded.proficiency_level, verified_by = null, verified_at = null
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'employee_skill_set', 'employee_skills', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.set_employee_skill(uuid, uuid, public.proficiency_level) from public, anon;
grant execute on function public.set_employee_skill(uuid, uuid, public.proficiency_level) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.verify_employee_skill(p_employee_skill_id uuid)
returns public.employee_skills
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.employee_skills;
begin
  select tenant_id into v_tenant_id from public.employee_skills where id = p_employee_skill_id for update;
  if not found then
    raise exception 'not_found: no employee skill %', p_employee_skill_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify skills for this tenant';
  end if;

  update public.employee_skills set verified_by = auth.uid(), verified_at = now() where id = p_employee_skill_id returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'employee_skill_verified', 'employee_skills', p_employee_skill_id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.verify_employee_skill(uuid) from public, anon;
grant execute on function public.verify_employee_skill(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Qualifications/certifications.

create or replace function public.upsert_employee_qualification(
  p_id                    uuid,
  p_employee_id           uuid,
  p_credential_type       public.credential_type,
  p_name                  text,
  p_issuing_organization  text default null,
  p_issue_date            date default null,
  p_expiry_date           date default null,
  p_evidence_document_id  uuid default null
) returns public.employee_qualifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.employee_qualifications;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot manage qualifications for this tenant';
  end if;

  if p_id is null then
    insert into public.employee_qualifications (
      tenant_id, employee_id, credential_type, name, issuing_organization, issue_date, expiry_date, evidence_document_id
    ) values (
      v_tenant_id, p_employee_id, p_credential_type, p_name, p_issuing_organization, p_issue_date, p_expiry_date, p_evidence_document_id
    )
    returning * into v_result;

    perform public.write_audit_log(v_tenant_id, auth.uid(), 'employee_qualification_created', 'employee_qualifications', v_result.id, null, to_jsonb(v_result));
  else
    update public.employee_qualifications
      set name = p_name, issuing_organization = p_issuing_organization, issue_date = p_issue_date,
          expiry_date = p_expiry_date, evidence_document_id = coalesce(p_evidence_document_id, evidence_document_id),
          status = 'pending_verification', verified_by = null, verified_at = null
      where id = p_id and tenant_id = v_tenant_id
      returning * into v_result;

    if not found then
      raise exception 'not_found: no qualification % for this tenant', p_id;
    end if;

    perform public.write_audit_log(v_tenant_id, auth.uid(), 'employee_qualification_updated', 'employee_qualifications', p_id, null, to_jsonb(v_result));
  end if;

  return v_result;
end;
$$;

revoke execute on function public.upsert_employee_qualification(uuid, uuid, public.credential_type, text, text, date, date, uuid) from public, anon;
grant execute on function public.upsert_employee_qualification(uuid, uuid, public.credential_type, text, text, date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.verify_employee_qualification(p_id uuid, p_approve boolean)
returns public.employee_qualifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.employee_qualifications;
begin
  select tenant_id into v_tenant_id from public.employee_qualifications where id = p_id for update;
  if not found then
    raise exception 'not_found: no qualification %', p_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot verify qualifications for this tenant';
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

-- ---------------------------------------------------------------------------
create or replace function public.sync_expired_qualifications(p_tenant_id uuid)
returns setof public.employee_qualifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  if not public.can_manage_employees(p_tenant_id) then
    raise exception 'insufficient_privilege: cannot sync qualifications for this tenant';
  end if;

  for v_row in
    update public.employee_qualifications
    set status = 'expired'
    where tenant_id = p_tenant_id
      and status not in ('expired', 'revoked')
      and expiry_date is not null
      and expiry_date < current_date
    returning *
  loop
    perform public.write_audit_log(p_tenant_id, auth.uid(), 'employee_qualification_expired', 'employee_qualifications', v_row.id, null, jsonb_build_object('status', 'expired'));
    return next v_row;
  end loop;
end;
$$;

revoke execute on function public.sync_expired_qualifications(uuid) from public, anon;
grant execute on function public.sync_expired_qualifications(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Training.

create or replace function public.enroll_employee_training(p_training_program_id uuid, p_employee_id uuid)
returns public.training_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.training_enrollments;
begin
  select tenant_id into v_tenant_id from public.training_programs where id = p_training_program_id;
  if not found then
    raise exception 'not_found: no training program %', p_training_program_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot enroll employees in training for this tenant';
  end if;

  insert into public.training_enrollments (tenant_id, training_program_id, employee_id)
  values (v_tenant_id, p_training_program_id, p_employee_id)
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'training_enrollment_created', 'training_enrollments', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.enroll_employee_training(uuid, uuid) from public, anon;
grant execute on function public.enroll_employee_training(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.complete_employee_training(
  p_enrollment_id uuid,
  p_status        public.training_enrollment_status,
  p_result        text default null
) returns public.training_enrollments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.training_enrollments;
begin
  select tenant_id into v_tenant_id from public.training_enrollments where id = p_enrollment_id for update;
  if not found then
    raise exception 'not_found: no training enrollment %', p_enrollment_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot complete training enrollments for this tenant';
  end if;

  if p_status not in ('completed', 'failed', 'cancelled') then
    raise exception 'invalid_transition: % is not a valid completion status', p_status;
  end if;

  update public.training_enrollments
    set status = p_status, result = p_result,
        completed_at = case when p_status in ('completed', 'failed') then now() else completed_at end
    where id = p_enrollment_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'training_enrollment_completed', 'training_enrollments', p_enrollment_id, null, jsonb_build_object('status', p_status));

  return v_result;
end;
$$;

revoke execute on function public.complete_employee_training(uuid, public.training_enrollment_status, text) from public, anon;
grant execute on function public.complete_employee_training(uuid, public.training_enrollment_status, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Performance reviews — a single stage-aware transition RPC. Each stage has
-- its own authorized actor: manager tier drives draft/manager_review and
-- the final lock; the employee themselves (their own row only) drives
-- their own acknowledgement step — never forgeable by another employee.

create or replace function public.create_performance_review(
  p_employee_id         uuid,
  p_reviewer_profile_id uuid,
  p_review_period_start date,
  p_review_period_end   date
) returns public.performance_reviews
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.performance_reviews;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot create performance reviews for this tenant';
  end if;

  insert into public.performance_reviews (tenant_id, employee_id, reviewer_profile_id, review_period_start, review_period_end)
  values (v_tenant_id, p_employee_id, p_reviewer_profile_id, p_review_period_start, p_review_period_end)
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'performance_review_created', 'performance_reviews', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.create_performance_review(uuid, uuid, date, date) from public, anon;
grant execute on function public.create_performance_review(uuid, uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.advance_performance_review(
  p_review_id        uuid,
  p_new_status       public.performance_review_status,
  p_manager_comments text default null,
  p_employee_comments text default null,
  p_overall_rating   numeric default null
) returns public.performance_reviews
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_employee_id uuid;
  v_old_status public.performance_review_status;
  v_is_self boolean;
  v_result public.performance_reviews;
begin
  select r.tenant_id, r.employee_id, r.status, (e.profile_id = auth.uid())
    into v_tenant_id, v_employee_id, v_old_status, v_is_self
  from public.performance_reviews r
  join public.employees e on e.id = r.employee_id
  where r.id = p_review_id
  for update;

  if not found then
    raise exception 'not_found: no performance review %', p_review_id;
  end if;

  -- Stage-specific authorization: the employee's own acknowledgement step
  -- is theirs alone; every other step requires the manager tier.
  if v_old_status = 'employee_review' and p_new_status = 'acknowledgement' then
    if not v_is_self then
      raise exception 'insufficient_privilege: only the reviewed employee can acknowledge their own review';
    end if;
  elsif not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot advance this performance review';
  end if;

  update public.performance_reviews
    set status = p_new_status,
        manager_comments = coalesce(p_manager_comments, manager_comments),
        employee_comments = coalesce(p_employee_comments, employee_comments),
        overall_rating = coalesce(p_overall_rating, overall_rating),
        finalized_at = case when p_new_status = 'finalized' then now() else finalized_at end
    where id = p_review_id
    returning * into v_result;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'performance_review_advanced', 'performance_reviews', p_review_id,
    jsonb_build_object('status', v_old_status), jsonb_build_object('status', p_new_status)
  );

  return v_result;
end;
$$;

revoke execute on function public.advance_performance_review(uuid, public.performance_review_status, text, text, numeric) from public, anon;
grant execute on function public.advance_performance_review(uuid, public.performance_review_status, text, text, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- Development actions.

create or replace function public.add_development_action(
  p_employee_id     uuid,
  p_goal            text,
  p_owner_profile_id uuid default null,
  p_target_date     date default null,
  p_review_id       uuid default null
) returns public.development_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_result public.development_actions;
begin
  select tenant_id into v_tenant_id from public.employees where id = p_employee_id;
  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot add development actions for this tenant';
  end if;

  insert into public.development_actions (tenant_id, employee_id, review_id, goal, owner_profile_id, target_date)
  values (v_tenant_id, p_employee_id, p_review_id, p_goal, p_owner_profile_id, p_target_date)
  returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'development_action_added', 'development_actions', v_result.id, null, to_jsonb(v_result));

  return v_result;
end;
$$;

revoke execute on function public.add_development_action(uuid, text, uuid, date, uuid) from public, anon;
grant execute on function public.add_development_action(uuid, text, uuid, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
create or replace function public.update_development_action_status(p_id uuid, p_status text)
returns public.development_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_owner_profile_id uuid;
  v_result public.development_actions;
begin
  select tenant_id, owner_profile_id into v_tenant_id, v_owner_profile_id from public.development_actions where id = p_id for update;
  if not found then
    raise exception 'not_found: no development action %', p_id;
  end if;

  if v_owner_profile_id <> auth.uid() and not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: only the action owner or an HR/management role may update this action';
  end if;

  if p_status not in ('open', 'in_progress', 'completed') then
    raise exception 'invalid_status: % is not a valid development-action status', p_status;
  end if;

  update public.development_actions
    set status = p_status, completed_at = case when p_status = 'completed' then now() else null end
    where id = p_id
    returning * into v_result;

  perform public.write_audit_log(v_tenant_id, auth.uid(), 'development_action_status_updated', 'development_actions', p_id, null, jsonb_build_object('status', p_status));

  return v_result;
end;
$$;

revoke execute on function public.update_development_action_status(uuid, text) from public, anon;
grant execute on function public.update_development_action_status(uuid, text) to authenticated;
