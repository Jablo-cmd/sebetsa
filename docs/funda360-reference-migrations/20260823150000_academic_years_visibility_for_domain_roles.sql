-- Academic Years visibility for Fees/Behaviour domain roles
--
-- Bug found during live verification: finance_manager/accountant
-- (learner.view_financial) and vice_principal/department_head
-- (learner.view_behaviour) do not hold academic.view, so
-- can_view_academic() — and therefore the existing academic_years_select
-- policy — excludes them. Every learner_fee_charges/learner_fee_payments/
-- behaviour_incidents row requires an academic_year_id, and the frontend
-- resolves "the current academic year" via AcademicProvider, which simply
-- cannot load *any* row from `academic_years` for these four roles. Their
-- "Add charge"/"Record payment"/"Record incident" actions were silently
-- unusable — not blocked by permission, just missing the year id they
-- need to submit.
--
-- Fix: an additional, narrow, purely-additive SELECT policy on
-- academic_years only (multiple permissive RLS policies for the same
-- command combine with OR) for exactly these four roles. This does NOT
-- touch can_view_academic() itself, so grades/classes/subjects/terms/
-- teaching_assignments visibility is completely unaffected — these roles
-- gain only enough to know which academic year is current, not the
-- academic structure built under it.
create or replace function public.can_view_academic_years_for_domain_roles(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    target_school_id = public.current_tenant_id()
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
      ('finance_manager', 'accountant', 'vice_principal', 'department_head')
$$;

comment on function public.can_view_academic_years_for_domain_roles(uuid) is
  'Narrow SELECT-only extension of academic_years visibility for the Fees/Behaviour domain roles, who need to resolve "the current academic year" for their own records but hold no general academic.view access. Deliberately separate from can_view_academic() so grades/classes/subjects/terms remain unaffected. Keep in sync manually with learner.view_financial/learner.view_behaviour role grants in ROLE_PERMISSIONS.';

grant execute on function public.can_view_academic_years_for_domain_roles(uuid) to authenticated;

create policy academic_years_select_for_domain_roles on public.academic_years
  for select to authenticated using (public.can_view_academic_years_for_domain_roles(school_id));
