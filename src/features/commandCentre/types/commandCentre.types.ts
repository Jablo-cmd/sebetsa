/**
 * Domain types for the Operations Command Centre + operational alert engine
 * (supabase/migrations/20260921090200_command_centre_alerts.sql,
 * 20260921090300_emergency_response.sql).
 */

export interface CommandCentreSnapshot {
  workforceTotalScheduled: number;
  workforceClockedIn: number;
  workforceAbsent: number;
  workforceLate: number;
  workforcePendingExceptions: number;
  sitesTotalActive: number;
  sitesUnderstaffed: number;
  sitesUncovered: number;
  patrolsActive: number;
  patrolsCompletedToday: number;
  patrolsMissed: number;
  complianceExpired: number;
  complianceExpiringSoon: number;
  incidentsOpen: number;
  incidentsCritical: number;
  incidentsOverdue: number;
  tasksOverdue: number;
  tasksVerificationPending: number;
  contractsActive: number;
  contractsSlaBreaching: number;
  emergenciesActive: number;
  alertsOpen: number;
  alertsCritical: number;
}

export type AlertSeverity = 'info' | 'warning' | 'critical';
export type AlertStatus = 'open' | 'acknowledged' | 'resolved';
export type OperationalAlertType =
  | 'site_understaffed'
  | 'employee_absent'
  | 'employee_late'
  | 'patrol_missed'
  | 'checkpoint_missed'
  | 'qualification_expired'
  | 'contract_sla_breach'
  | 'incident_overdue'
  | 'critical_task_overdue'
  | 'excessive_overtime'
  | 'emergency_active';

export interface OperationalAlert {
  id: string;
  tenantId: string;
  alertType: OperationalAlertType;
  severity: AlertSeverity;
  siteId: string | null;
  employeeId: string | null;
  contractId: string | null;
  message: string;
  status: AlertStatus;
  acknowledgedBy: string | null;
  acknowledgedAt: string | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
  resolutionNotes: string | null;
  createdAt: string;
}
