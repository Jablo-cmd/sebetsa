-- Behaviour guardian visibility (FND-WELL-002 / FND-PAR-005)
--
-- parent_portal_v1's own header explicitly deferred Behaviour: "no column
-- or flag distinguishing guardian-appropriate information from internal
-- staff-only notes (action_taken, outcome are free-text staff commentary
-- with no visibility tier)... A future migration introducing a real
-- visibility model (e.g. a `guardian_visible` flag, or a parallel
-- guardian-facing summary table) is required before Behaviour can appear
-- in the Parent Portal." This is that migration.
--
-- Two-part design, chosen deliberately over a single new RLS SELECT policy:
--
-- 1. `guardian_visible` (boolean, default false) — a staff-set flag on the
--    incident itself, exactly the option parent_portal_v1 named. Staff
--    already have UPDATE on the full row via can_manage_behaviour(), so no
--    new column-grant plumbing is needed for staff to set it.
--
-- 2. A guardian-facing READ still cannot come from a plain RLS SELECT
--    policy on behaviour_incidents: RLS is row-level, not column-level, so
--    any policy that lets a guardian SELECT a guardian_visible=true row
--    would also hand them action_taken/outcome/follow_up_notes — exactly
--    the internal-staff-commentary leak parent_portal_v1 refused to ship.
--    Instead, guardians read through a new SECURITY DEFINER RPC,
--    get_guardian_visible_behaviour_incidents(), that projects only the
--    columns that are safe for a guardian to see (type, severity, category,
--    when, description, follow_up_required) and re-checks
--    is_learner_guardian() itself. This mirrors the existing SECURITY
--    DEFINER-RPC-as-front-door pattern used for privileged writes
--    elsewhere in this schema, applied here to a privileged, narrowed read.
--    No new RLS policy is added to behaviour_incidents itself — staff
--    access is unchanged, and guardians get no direct table grant at all.

alter table public.behaviour_incidents
  add column guardian_visible boolean not null default false;

comment on column public.behaviour_incidents.guardian_visible is
  'Staff-set flag: when true, this incident''s type/severity/category/date/description/follow_up_required (never action_taken/outcome/follow_up_notes — internal staff commentary) is readable by the learner''s guardians via get_guardian_visible_behaviour_incidents(). Defaults to false — nothing is guardian-visible unless a staff member explicitly opts it in.';

create or replace function public.get_guardian_visible_behaviour_incidents(p_learner_id uuid)
returns table (
  id                  uuid,
  learner_id          uuid,
  incident_type       public.behaviour_incident_type,
  severity            public.behaviour_severity,
  category            text,
  occurred_at         timestamptz,
  description         text,
  follow_up_required  boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select bi.id, bi.learner_id, bi.incident_type, bi.severity, bi.category, bi.occurred_at, bi.description, bi.follow_up_required
  from public.behaviour_incidents bi
  where bi.learner_id = p_learner_id
    and bi.guardian_visible = true
    and bi.active = true
    and public.is_learner_guardian(p_learner_id)
  order by bi.occurred_at desc
$$;

comment on function public.get_guardian_visible_behaviour_incidents(uuid) is
  'Guardian-facing read of behaviour_incidents, deliberately column-narrowed (excludes action_taken/outcome/follow_up_notes — internal staff commentary per parent_portal_v1''s own documented reason for excluding Behaviour entirely) and row-narrowed (guardian_visible=true, active=true, and is_learner_guardian(p_learner_id) re-checked inside the function). SECURITY DEFINER is required only to read behaviour_incidents at all under FORCE ROW LEVEL SECURITY with no guardian-facing table policy; the is_learner_guardian() check inside is what actually authorises the caller, exactly mirroring how other SECURITY DEFINER validate-trigger functions in this schema gate on a re-checked condition rather than trusting the caller''s role.';

grant execute on function public.get_guardian_visible_behaviour_incidents(uuid) to authenticated;
