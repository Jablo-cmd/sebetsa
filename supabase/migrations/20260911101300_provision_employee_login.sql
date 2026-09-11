-- Sebetsa Phase D — Employee Login Provisioning
-- Employee != application user (see employees.profile_id comment in
-- 20260911100600). This is the one path that gives an existing employee
-- record application access: it creates the auth user via admin_create_user
-- and links employees.profile_id back to it, atomically.

create or replace function public.provision_employee_login(
  p_employee_id uuid,
  p_role public.user_role,
  p_phone text default null
)
returns table (user_id uuid, temporary_password text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant_id uuid;
  v_first_name text;
  v_last_name text;
  v_email text;
  v_existing_profile_id uuid;
  v_result record;
begin
  select tenant_id, first_name, last_name, email, profile_id
    into v_tenant_id, v_first_name, v_last_name, v_email, v_existing_profile_id
    from public.employees where id = p_employee_id;

  if not found then
    raise exception 'not_found: no employee %', p_employee_id;
  end if;

  if not public.can_manage_employees(v_tenant_id) then
    raise exception 'insufficient_privilege: cannot manage employees for this organization';
  end if;

  if v_existing_profile_id is not null then
    raise exception 'already_provisioned: employee % already has a linked login', p_employee_id;
  end if;

  if v_email is null then
    raise exception 'missing_email: employee has no email on file to provision a login for';
  end if;

  select * into v_result from public.admin_create_user(v_email, v_first_name, v_last_name, p_phone, p_role, v_tenant_id);

  update public.employees set profile_id = v_result.user_id where id = p_employee_id;

  perform public.write_audit_log(
    v_tenant_id, auth.uid(), 'employee_login_provisioned', 'employees', p_employee_id,
    null, jsonb_build_object('profile_id', v_result.user_id, 'role', p_role)
  );

  return query select v_result.user_id, v_result.temporary_password;
end;
$$;

grant execute on function public.provision_employee_login(uuid, public.user_role, text) to authenticated;
