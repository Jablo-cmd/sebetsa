import { supabase } from '@/lib/supabase';
import type { OperationalAlertRow } from '@/lib/dbTypes';
import type { CommandCentreSnapshot, OperationalAlert } from '@/features/commandCentre/types/commandCentre.types';

function toOperationalAlert(row: OperationalAlertRow): OperationalAlert {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    alertType: row.alert_type,
    severity: row.severity,
    siteId: row.site_id,
    employeeId: row.employee_id,
    contractId: row.contract_id,
    message: row.message,
    status: row.status,
    acknowledgedBy: row.acknowledged_by,
    acknowledgedAt: row.acknowledged_at,
    resolvedBy: row.resolved_by,
    resolvedAt: row.resolved_at,
    resolutionNotes: row.resolution_notes,
    createdAt: row.created_at,
  };
}

/**
 * SECURITY INVOKER, RLS-riding — every figure here is a live aggregate over
 * tables the caller's own role already has RLS access to. No client-side
 * aggregation of large datasets, no hardcoded figures.
 */
async function getSnapshot(tenantId: string): Promise<CommandCentreSnapshot> {
  const { data, error } = await supabase.rpc('get_command_centre_snapshot', { p_tenant_id: tenantId });
  if (error) throw error;
  const row = data[0];
  return {
    workforceTotalScheduled: row?.workforce_total_scheduled ?? 0,
    workforceClockedIn: row?.workforce_clocked_in ?? 0,
    workforceAbsent: row?.workforce_absent ?? 0,
    workforceLate: row?.workforce_late ?? 0,
    workforcePendingExceptions: row?.workforce_pending_exceptions ?? 0,
    sitesTotalActive: row?.sites_total_active ?? 0,
    sitesUnderstaffed: row?.sites_understaffed ?? 0,
    sitesUncovered: row?.sites_uncovered ?? 0,
    patrolsActive: row?.patrols_active ?? 0,
    patrolsCompletedToday: row?.patrols_completed_today ?? 0,
    patrolsMissed: row?.patrols_missed ?? 0,
    complianceExpired: row?.compliance_expired ?? 0,
    complianceExpiringSoon: row?.compliance_expiring_soon ?? 0,
    incidentsOpen: row?.incidents_open ?? 0,
    incidentsCritical: row?.incidents_critical ?? 0,
    incidentsOverdue: row?.incidents_overdue ?? 0,
    tasksOverdue: row?.tasks_overdue ?? 0,
    tasksVerificationPending: row?.tasks_verification_pending ?? 0,
    contractsActive: row?.contracts_active ?? 0,
    contractsSlaBreaching: row?.contracts_sla_breaching ?? 0,
    emergenciesActive: row?.emergencies_active ?? 0,
    alertsOpen: row?.alerts_open ?? 0,
    alertsCritical: row?.alerts_critical ?? 0,
  };
}

/** Capped, not a full unbounded table scan — a busy tenant's resolved-alert history can run into the thousands; the inbox only ever needs the most recent page. */
async function getAlerts(tenantId: string, status?: OperationalAlert['status'], limit = 100): Promise<OperationalAlert[]> {
  let query = supabase.from('operational_alerts').select('*').eq('tenant_id', tenantId);
  if (status) query = query.eq('status', status);
  const { data, error } = await query.order('created_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return data.map(toOperationalAlert);
}

async function acknowledgeAlert(alertId: string): Promise<OperationalAlert> {
  const { data, error } = await supabase.rpc('acknowledge_operational_alert', { p_alert_id: alertId });
  if (error) throw error;
  return toOperationalAlert(data);
}

async function resolveAlert(alertId: string, resolutionNotes?: string): Promise<OperationalAlert> {
  const { data, error } = await supabase.rpc('resolve_operational_alert', { p_alert_id: alertId, p_resolution_notes: resolutionNotes });
  if (error) throw error;
  return toOperationalAlert(data);
}

async function reopenAlert(alertId: string, reason: string): Promise<OperationalAlert> {
  const { data, error } = await supabase.rpc('reopen_operational_alert', { p_alert_id: alertId, p_reason: reason });
  if (error) throw error;
  return toOperationalAlert(data);
}

export const commandCentreService = {
  getSnapshot,
  getAlerts,
  acknowledgeAlert,
  resolveAlert,
  reopenAlert,
};
