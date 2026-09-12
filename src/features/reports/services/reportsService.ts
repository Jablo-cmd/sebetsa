import { supabase } from '@/lib/supabase';

export interface OperationalMetrics {
  activeEmployeeCount: number;
  attendanceRatePct: number;
  lateAttendanceCount: number;
  pendingLeaveRequests: number;
  approvedLeaveDays: number;
  taskCompletionRatePct: number;
  overdueTaskCount: number;
  openIncidentCount: number;
  criticalIncidentCount: number;
  activeAssetCount: number;
  assetsInMaintenanceCount: number;
  activeContractCount: number;
  contractsExpiringCount: number;
  qualificationsExpiringCount: number;
  trainingsCompletedCount: number;
}

/**
 * Calls the SECURITY INVOKER get_operational_metrics() RPC — every figure
 * it returns is already scoped to what the signed-in caller's own RLS
 * permits, so this service does no additional role filtering itself.
 */
async function getOperationalMetrics(tenantId: string, periodStart: string, periodEnd: string): Promise<OperationalMetrics | null> {
  const { data, error } = await supabase.rpc('get_operational_metrics', {
    p_tenant_id: tenantId,
    p_period_start: periodStart,
    p_period_end: periodEnd,
  });
  if (error) throw error;
  const row = data?.[0];
  if (!row) return null;
  return {
    activeEmployeeCount: row.active_employee_count,
    attendanceRatePct: row.attendance_rate_pct,
    lateAttendanceCount: row.late_attendance_count,
    pendingLeaveRequests: row.pending_leave_requests,
    approvedLeaveDays: row.approved_leave_days,
    taskCompletionRatePct: row.task_completion_rate_pct,
    overdueTaskCount: row.overdue_task_count,
    openIncidentCount: row.open_incident_count,
    criticalIncidentCount: row.critical_incident_count,
    activeAssetCount: row.active_asset_count,
    assetsInMaintenanceCount: row.assets_in_maintenance_count,
    activeContractCount: row.active_contract_count,
    contractsExpiringCount: row.contracts_expiring_count,
    qualificationsExpiringCount: row.qualifications_expiring_count,
    trainingsCompletedCount: row.trainings_completed_count,
  };
}

export const reportsService = { getOperationalMetrics };
