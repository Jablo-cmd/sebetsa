import { supabase } from '@/lib/supabase';
import type { PatrolRouteRow, PatrolRunRow, PatrolCheckpointScanRow } from '@/lib/dbTypes';
import type { PatrolRoute, PatrolRun, PatrolCheckpointScan, PatrolSummary, CheckpointScanType } from '@/features/patrols/types/patrol.types';
import type { DeviceLocation } from '@/features/attendance/types/attendance.types';

function toPatrolRoute(row: PatrolRouteRow): PatrolRoute {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    name: row.name,
    expectedDurationMinutes: row.expected_duration_minutes,
    allowedStartWindowMinutes: row.allowed_start_window_minutes,
    completionThresholdPct: row.completion_threshold_pct,
    active: row.active,
  };
}

function toPatrolRun(row: PatrolRunRow): PatrolRun {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    patrolRouteId: row.patrol_route_id,
    siteId: row.site_id,
    employeeId: row.employee_id,
    status: row.status,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    expectedCheckpointCount: row.expected_checkpoint_count,
    scannedCheckpointCount: row.scanned_checkpoint_count,
  };
}

function toPatrolCheckpointScan(row: PatrolCheckpointScanRow): PatrolCheckpointScan {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    patrolRunId: row.patrol_run_id,
    checkpointId: row.checkpoint_id,
    scannedCode: row.scanned_code,
    employeeId: row.employee_id,
    sequenceNumber: row.sequence_number,
    scannedAt: row.scanned_at,
    scanMethod: row.scan_method,
    latitude: row.latitude,
    longitude: row.longitude,
    verificationResult: row.verification_result,
    riskFlags: row.risk_flags,
  };
}

/** Active patrol routes for a site — what an employee assigned there may start. */
async function getActiveRoutesForSite(siteId: string): Promise<PatrolRoute[]> {
  const { data, error } = await supabase.from('patrol_routes').select('*').eq('site_id', siteId).eq('active', true).order('name');
  if (error) throw error;
  return data.map(toPatrolRoute);
}

/** The caller's own in-progress patrol run, if any. */
async function getMyActiveRun(employeeId: string): Promise<PatrolRun | null> {
  const { data, error } = await supabase
    .from('patrol_runs')
    .select('*')
    .eq('employee_id', employeeId)
    .eq('status', 'in_progress')
    .order('started_at', { ascending: false })
    .maybeSingle();
  if (error) throw error;
  return data ? toPatrolRun(data) : null;
}

async function getScansForRun(patrolRunId: string): Promise<PatrolCheckpointScan[]> {
  const { data, error } = await supabase.from('patrol_checkpoint_scans').select('*').eq('patrol_run_id', patrolRunId).order('sequence_number');
  if (error) throw error;
  return data.map(toPatrolCheckpointScan);
}

async function startPatrol(patrolRouteId: string): Promise<PatrolRun> {
  const { data, error } = await supabase.rpc('start_patrol', { p_patrol_route_id: patrolRouteId });
  if (error) throw error;
  return toPatrolRun(data);
}

/**
 * Every anti-abuse check (sequence, duplicate, window, invalid checkpoint)
 * happens server-side — this call always succeeds unless the run itself is
 * invalid; a bad scan comes back as evidence (verificationResult), not an
 * error, matching scan_checkpoint()'s own deliberate design.
 */
async function scanCheckpoint(
  patrolRunId: string,
  checkpointCode: string,
  location: DeviceLocation | null,
  scanMethod: CheckpointScanType,
): Promise<{ scan: PatrolCheckpointScan; run: PatrolRun }> {
  const { data, error } = await supabase.rpc('scan_checkpoint', {
    p_patrol_run_id: patrolRunId,
    p_checkpoint_code: checkpointCode,
    p_latitude: location?.latitude,
    p_longitude: location?.longitude,
    p_scan_method: scanMethod,
  });
  if (error) throw error;
  const row = data[0];
  if (!row) throw new Error('scan_checkpoint returned no row');
  return { scan: toPatrolCheckpointScan(row.scan), run: toPatrolRun(row.run) };
}

async function completePatrol(patrolRunId: string): Promise<PatrolRun> {
  const { data, error } = await supabase.rpc('complete_patrol', { p_patrol_run_id: patrolRunId });
  if (error) throw error;
  return toPatrolRun(data);
}

async function getPatrolSummary(tenantId: string, since?: string): Promise<PatrolSummary> {
  const { data, error } = await supabase.rpc('get_patrol_summary', { p_tenant_id: tenantId, p_since: since });
  if (error) throw error;
  const row = data[0];
  return {
    activePatrols: row?.active_patrols ?? 0,
    completedPatrols: row?.completed_patrols ?? 0,
    incompletePatrols: row?.incomplete_patrols ?? 0,
    missedCheckpoints: row?.missed_checkpoints ?? 0,
    lateCheckpoints: row?.late_checkpoints ?? 0,
    exceptionRate: row?.exception_rate ?? 0,
  };
}

/** Recent patrol runs across the tenant, most recent first — oversight view. */
async function getRecentRuns(tenantId: string, limit = 25): Promise<PatrolRun[]> {
  const { data, error } = await supabase.from('patrol_runs').select('*').eq('tenant_id', tenantId).order('started_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return data.map(toPatrolRun);
}

export const patrolService = {
  getActiveRoutesForSite,
  getMyActiveRun,
  getScansForRun,
  startPatrol,
  scanCheckpoint,
  completePatrol,
  getPatrolSummary,
  getRecentRuns,
};
