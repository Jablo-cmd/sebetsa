/**
 * Domain types for guard tours / checkpoint patrols
 * (supabase/migrations/20260921090100_guard_tours.sql).
 */

export type PatrolRunStatus = 'in_progress' | 'completed' | 'incomplete' | 'abandoned';
export type CheckpointScanType = 'qr' | 'nfc' | 'manual';
export type CheckpointScanResult = 'valid' | 'wrong_sequence' | 'duplicate' | 'out_of_window' | 'invalid_checkpoint' | 'not_assigned';

export interface PatrolRoute {
  id: string;
  tenantId: string;
  siteId: string;
  name: string;
  expectedDurationMinutes: number | null;
  allowedStartWindowMinutes: number;
  completionThresholdPct: number;
  active: boolean;
}

export interface PatrolRun {
  id: string;
  tenantId: string;
  patrolRouteId: string;
  siteId: string;
  employeeId: string;
  status: PatrolRunStatus;
  startedAt: string;
  completedAt: string | null;
  expectedCheckpointCount: number;
  scannedCheckpointCount: number;
}

export interface PatrolCheckpointScan {
  id: string;
  tenantId: string;
  patrolRunId: string;
  checkpointId: string | null;
  scannedCode: string | null;
  employeeId: string;
  sequenceNumber: number;
  scannedAt: string;
  scanMethod: CheckpointScanType;
  latitude: number | null;
  longitude: number | null;
  verificationResult: CheckpointScanResult;
  riskFlags: unknown;
}

export interface PatrolSummary {
  activePatrols: number;
  completedPatrols: number;
  incompletePatrols: number;
  missedCheckpoints: number;
  lateCheckpoints: number;
  exceptionRate: number;
}
