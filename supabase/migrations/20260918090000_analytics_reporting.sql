-- Sebetsa Phase R — Analytics, Reporting & Management Intelligence.
--
-- get_operational_metrics() is deliberately SECURITY INVOKER (the default —
-- no `security definer` clause anywhere in this file). Every other
-- privileged RPC in Sebetsa (Phase H onward) is SECURITY DEFINER with its
-- own explicit permission check; this one is the one deliberate exception,
-- and for a specific reason: it must NEVER see more than the calling
-- role's own RLS already permits. Making it SECURITY DEFINER would silently
-- turn it into a cross-tenant, cross-role data leak — an employee calling
-- it would suddenly see management-only aggregates. Running as the caller
-- means every subquery below is filtered live by that table's own existing
-- RLS policies (the same ones already governing the underlying feature
-- pages), so role-appropriate reporting (R.3) falls out for free from
-- infrastructure that already exists, rather than being reimplemented here.
--
-- Every figure is a real aggregate over Sebetsa's own operational tables,
-- computed at call time — never a fabricated or hard-coded number (R.1/R.2).
-- No materialized view or scheduled aggregate table is introduced: at
-- Sebetsa's current scale, direct RLS-respecting aggregate queries are the
-- simplest architecture that satisfies R.1's "use the simplest architecture
-- that can support expected scale" — revisit only if/when query cost
-- becomes measurable.

create or replace function public.get_operational_metrics(
  p_tenant_id     uuid,
  p_period_start  date,
  p_period_end    date
) returns table (
  active_employee_count       bigint,
  attendance_rate_pct         numeric,
  late_attendance_count       bigint,
  pending_leave_requests      bigint,
  approved_leave_days         numeric,
  task_completion_rate_pct    numeric,
  overdue_task_count          bigint,
  open_incident_count         bigint,
  critical_incident_count     bigint,
  active_asset_count          bigint,
  assets_in_maintenance_count bigint,
  active_contract_count       bigint,
  contracts_expiring_count    bigint,
  qualifications_expiring_count bigint,
  trainings_completed_count   bigint
)
language sql
stable
as $$
  select
    (select count(*) from public.employees where tenant_id = p_tenant_id and employment_status = 'active'),

    (select coalesce(
      100.0 * count(*) filter (where status in ('present', 'late')) / nullif(count(*), 0), 0
     )
     from public.attendance_records
     where tenant_id = p_tenant_id and created_at::date between p_period_start and p_period_end),

    (select count(*) from public.attendance_records
     where tenant_id = p_tenant_id and status = 'late' and created_at::date between p_period_start and p_period_end),

    (select count(*) from public.leave_requests where tenant_id = p_tenant_id and status = 'pending'),

    (select coalesce(sum(
       least(end_date, p_period_end) - greatest(start_date, p_period_start) + 1
     ), 0)
     from public.leave_requests
     where tenant_id = p_tenant_id and status = 'approved'
       and start_date <= p_period_end and end_date >= p_period_start),

    (select coalesce(
      100.0 * count(*) filter (where status in ('completed', 'verified')) / nullif(count(*), 0), 0
     )
     from public.tasks
     where tenant_id = p_tenant_id and due_at is not null and due_at::date between p_period_start and p_period_end),

    (select count(*) from public.tasks
     where tenant_id = p_tenant_id and status in ('open', 'in_progress') and due_at is not null and due_at < now()),

    (select count(*) from public.incidents where tenant_id = p_tenant_id and status <> 'closed'),

    (select count(*) from public.incidents where tenant_id = p_tenant_id and severity = 'critical' and status <> 'closed'),

    (select count(*) from public.assets where tenant_id = p_tenant_id and status not in ('retired', 'disposed')),

    (select count(*) from public.assets where tenant_id = p_tenant_id and status = 'maintenance'),

    (select count(*) from public.contracts where tenant_id = p_tenant_id and status = 'active'),

    (select count(*) from public.contracts
     where tenant_id = p_tenant_id
       and (
         status = 'expiring'
         or (status = 'active' and end_date is not null and end_date between current_date and current_date + interval '30 days')
       )),

    (select count(*) from public.employee_qualifications
     where tenant_id = p_tenant_id and status = 'verified' and expiry_date is not null and expiry_date between current_date and current_date + interval '30 days'),

    (select count(*) from public.training_enrollments
     where tenant_id = p_tenant_id and status = 'completed' and completed_at::date between p_period_start and p_period_end)
$$;

revoke execute on function public.get_operational_metrics(uuid, date, date) from public, anon;
grant execute on function public.get_operational_metrics(uuid, date, date) to authenticated;

comment on function public.get_operational_metrics(uuid, date, date) is
  'SECURITY INVOKER by design — see the file header. Every column is a real aggregate over Sebetsa operational tables, scoped by the caller''s own existing RLS.';
