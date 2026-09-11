-- Widen can_view_learners() for the new Fees and Behaviour domains
--
-- finance_manager/accountant (learner.view_financial) and vice_principal/
-- department_head (learner.view_behaviour) gained real RLS access to the
-- new learner_fee_* and behaviour_incidents rows in the two preceding
-- migrations, but the Learner 360 page they use to reach that data opens
-- through the `learners` table itself — gated by can_view_learners(),
-- which none of these four roles held. Without this, the permission grant
-- is dead: they could never open a learner to see the tab their new
-- permission unlocks.
--
-- This is a deliberate, scoped widening of a READ-only function, chosen
-- explicitly over a narrower identity-only RPC after conferring on the
-- trade-off: these four roles gain the ability to view the full learner
-- record (identity, enrolment, guardians, emergency contacts, documents —
-- everything learner_enrollments_select/learner_guardians_select/
-- learner_emergency_contacts_select/learner_documents_select already gate
-- via this same function), not merely their own new tab. That is the
-- intended "real 360 view" outcome, not a side effect.
--
-- can_manage_learners() is deliberately NOT widened — these four roles
-- still cannot create/edit a learner's core identity, enrolment, or
-- guardians; their write access remains scoped to their own new domain via
-- can_manage_learner_financial()/can_manage_behaviour().

create or replace function public.can_view_learners(target_school_id uuid)
returns boolean
language sql
stable
as $$
  select
    (
      target_school_id = public.current_tenant_id()
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in
        (
          'school_owner', 'principal', 'admissions_officer', 'medical_officer',
          'finance_manager', 'accountant', 'vice_principal', 'department_head'
        )
    )
    or public.is_platform_admin()
$$;

comment on function public.can_view_learners(uuid) is
  'Mirrors the app-level learner.view permission (ROLE_PERMISSIONS in src/features/rbac/constants/rolePermissions.ts). Widened 2026-08-23 to include finance_manager/accountant/vice_principal/department_head so they can open a learner''s Learner 360 page to reach their new learner.view_financial/learner.view_behaviour tabs. Keep in sync manually.';
