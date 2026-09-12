import { supabase } from '@/lib/supabase';
import type { LeaveRequestRow } from '@/lib/dbTypes';
import type { LeaveRequest, LeaveRequestSummary, SubmitLeaveRequestInput, AffectedShift } from '@/features/leave/types/leave.types';

const SUMMARY_COLUMNS =
  'id, tenant_id, employee_id, leave_type_id, start_date, end_date, is_half_day, half_day_period, status, decided_by, decided_at, cancelled_at, cancelled_by, created_at, updated_at';

function toLeaveRequest(row: LeaveRequestRow): LeaveRequest {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    leaveTypeId: row.leave_type_id,
    startDate: row.start_date,
    endDate: row.end_date,
    isHalfDay: row.is_half_day,
    halfDayPeriod: row.half_day_period as 'am' | 'pm' | null,
    reason: row.reason,
    status: row.status,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    decisionNotes: row.decision_notes,
    supportingDocumentRef: row.supporting_document_ref,
    cancelledAt: row.cancelled_at,
    cancelledBy: row.cancelled_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** All leave requests visible to the caller under RLS — own rows for a plain
 * employee, tenant-wide for a leave.view-broad role (see can_view_leave_broad). */
async function getLeaveRequests(tenantId: string, filters: { employeeId?: string; status?: string } = {}): Promise<LeaveRequest[]> {
  let query = supabase.from('leave_requests').select('*').eq('tenant_id', tenantId);
  if (filters.employeeId) query = query.eq('employee_id', filters.employeeId);
  if (filters.status) query = query.eq('status', filters.status);
  const { data, error } = await query.order('start_date', { ascending: false });
  if (error) throw error;
  return data.map(toLeaveRequest);
}

async function submitLeaveRequest(input: SubmitLeaveRequestInput): Promise<LeaveRequest> {
  const { data, error } = await supabase.rpc('submit_leave_request', {
    p_employee_id: input.employeeId,
    p_leave_type_id: input.leaveTypeId,
    p_start_date: input.startDate,
    p_end_date: input.endDate,
    p_is_half_day: input.isHalfDay,
    p_half_day_period: input.halfDayPeriod ?? undefined,
    p_reason: input.reason ?? undefined,
    p_supporting_document_ref: input.supportingDocumentRef ?? undefined,
  });
  if (error) throw error;
  return toLeaveRequest(data);
}

async function cancelLeaveRequest(id: string): Promise<LeaveRequest> {
  const { data, error } = await supabase.rpc('cancel_leave_request', { p_leave_request_id: id });
  if (error) throw error;
  return toLeaveRequest(data);
}

async function approveLeaveRequest(id: string, decisionNotes?: string): Promise<LeaveRequest> {
  const { data, error } = await supabase.rpc('approve_leave_request', {
    p_leave_request_id: id,
    p_decision_notes: decisionNotes ?? undefined,
  });
  if (error) throw error;
  return toLeaveRequest(data);
}

async function rejectLeaveRequest(id: string, decisionNotes?: string): Promise<LeaveRequest> {
  const { data, error } = await supabase.rpc('reject_leave_request', {
    p_leave_request_id: id,
    p_decision_notes: decisionNotes ?? undefined,
  });
  if (error) throw error;
  return toLeaveRequest(data);
}

async function revokeLeaveRequest(id: string, decisionNotes?: string): Promise<LeaveRequest> {
  const { data, error } = await supabase.rpc('revoke_leave_request', {
    p_leave_request_id: id,
    p_decision_notes: decisionNotes ?? undefined,
  });
  if (error) throw error;
  return toLeaveRequest(data);
}

/**
 * Field-level projection for viewers who hold leave.view but not
 * leave.approve/leave.manage (e.g. site_manager on a Team Leave calendar) —
 * never selects reason/decision_notes/supporting_document_ref, so those
 * values never leave the database for this call regardless of what the
 * UI renders (architecture §23/§37: RLS is row-level, this is the
 * field-level layer on top of it).
 */
async function getLeaveRequestsSummary(
  tenantId: string,
  filters: { employeeId?: string; status?: string } = {},
): Promise<LeaveRequestSummary[]> {
  let query = supabase.from('leave_requests').select(SUMMARY_COLUMNS).eq('tenant_id', tenantId);
  if (filters.employeeId) query = query.eq('employee_id', filters.employeeId);
  if (filters.status) query = query.eq('status', filters.status);
  const { data, error } = await query.order('start_date', { ascending: false });
  if (error) throw error;
  return (data as unknown as LeaveRequestRow[]).map((row) => {
    const full = toLeaveRequest(row);
    return {
      id: full.id,
      tenantId: full.tenantId,
      employeeId: full.employeeId,
      leaveTypeId: full.leaveTypeId,
      startDate: full.startDate,
      endDate: full.endDate,
      isHalfDay: full.isHalfDay,
      halfDayPeriod: full.halfDayPeriod,
      status: full.status,
      decidedBy: full.decidedBy,
      decidedAt: full.decidedAt,
      cancelledAt: full.cancelledAt,
      cancelledBy: full.cancelledBy,
      createdAt: full.createdAt,
      updatedAt: full.updatedAt,
    };
  });
}

async function getAffectedShifts(leaveRequestId: string): Promise<AffectedShift[]> {
  const { data, error } = await supabase.rpc('get_leave_affected_shifts', { p_leave_request_id: leaveRequestId });
  if (error) throw error;
  return (data ?? []).map((row) => ({
    id: row.id,
    siteId: row.site_id,
    employeeId: row.employee_id,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    status: row.status,
  }));
}

export const leaveService = {
  getLeaveRequests,
  getLeaveRequestsSummary,
  submitLeaveRequest,
  cancelLeaveRequest,
  approveLeaveRequest,
  rejectLeaveRequest,
  revokeLeaveRequest,
  getAffectedShifts,
};
