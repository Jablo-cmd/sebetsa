-- Sebetsa — P0 security remediation (production-readiness audit,
-- docs/PRODUCTION_READINESS_AUDIT.md, Critical finding C-5).
--
-- site_assignments had no server-side business-rule enforcement beyond
-- tenant matching: no check the employee is active, no check the site is
-- active. Combined with C-3 (terminated employees keeping access), a
-- terminated employee could be freshly assigned to a client site with no
-- rejection at any layer.
--
-- Extends the existing validate_site_assignment_tenant_refs() trigger
-- (already BEFORE INSERT OR UPDATE on site_assignments) rather than adding
-- a second trigger, since both are the same "is this row allowed to exist
-- as written" question. Both new checks are scoped to a row that
-- represents an OPEN/FUTURE assignment (end_date is null or in the
-- future) — editing metadata on an already-closed historical assignment
-- (e.g. correcting role_on_site on a role that ended years ago) is
-- untouched, matching "must not destroy historical assignments, only
-- prevent NEW operational activity."
--
-- Not added here (kept in scope with the audit's explicit C-5 wording):
-- overlap/exclusion constraints between concurrent assignments, and
-- contract-validity gating. Both remain tracked as P1/P2 items in
-- docs/SEBETSA_PRODUCTION_CHECKLIST.md.

create or replace function public.validate_site_assignment_tenant_refs()
returns trigger
language plpgsql
as $$
declare
  v_site public.sites;
  v_employee public.employees;
  v_is_open boolean;
begin
  select * into v_site from public.sites where id = new.site_id and tenant_id = new.tenant_id;
  if not found then
    raise exception 'cross_tenant_reference: site % does not belong to tenant %', new.site_id, new.tenant_id;
  end if;

  select * into v_employee from public.employees where id = new.employee_id and tenant_id = new.tenant_id;
  if not found then
    raise exception 'cross_tenant_reference: employee % does not belong to tenant %', new.employee_id, new.tenant_id;
  end if;

  v_is_open := new.end_date is null or new.end_date >= current_date;

  if v_is_open and v_employee.employment_status in ('terminated', 'suspended') then
    raise exception 'inactive_employee: employee % is terminated or suspended and cannot hold an open site assignment', new.employee_id;
  end if;

  if v_is_open and v_site.status <> 'active' then
    raise exception 'inactive_site: site % is not active (status: %) and cannot receive a new open assignment', new.site_id, v_site.status;
  end if;

  return new;
end;
$$;
