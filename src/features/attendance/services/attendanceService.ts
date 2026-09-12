import { supabase } from '@/lib/supabase';
import { fetchAllRows } from '@/lib/pagination';
import type { AttendanceRecordRow, AttendanceRecordInsert, AttendanceBreakRow, AttendanceCorrectionRow, AttendancePolicyRow } from '@/lib/dbTypes';
import type {
  AttendanceRecord,
  AttendanceEntry,
  AttendanceStatusCounts,
  RosterEmployee,
  AttendanceBreak,
  AttendanceCorrection,
  AttendanceCorrectionField,
  AttendancePolicy,
} from '@/features/attendance/types/attendance.types';
import { tallyStatusCounts } from '@/features/attendance/utils/calculations';

function toAttendanceRecord(row: AttendanceRecordRow): AttendanceRecord {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    shiftId: row.shift_id,
    siteId: row.site_id,
    employeeId: row.employee_id,
    status: row.status,
    clockInAt: row.clock_in_at,
    clockOutAt: row.clock_out_at,
    lateMinutes: row.late_minutes,
    earlyDepartureMinutes: row.early_departure_minutes,
    workedMinutes: row.worked_minutes,
    overtimeMinutes: row.overtime_minutes,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toAttendanceBreak(row: AttendanceBreakRow): AttendanceBreak {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    attendanceRecordId: row.attendance_record_id,
    breakStart: row.break_start,
    breakEnd: row.break_end,
  };
}

function toAttendanceCorrection(row: AttendanceCorrectionRow): AttendanceCorrection {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    attendanceRecordId: row.attendance_record_id,
    field: row.field,
    previousValue: row.previous_value,
    newValue: row.new_value,
    reason: row.reason,
    status: row.status,
    requestedBy: row.requested_by,
    reviewedBy: row.reviewed_by,
    reviewedAt: row.reviewed_at,
    reviewNotes: row.review_notes,
    createdAt: row.created_at,
  };
}

function toAttendancePolicy(row: AttendancePolicyRow): AttendancePolicy {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    gracePeriodMinutes: row.grace_period_minutes,
    earlyDepartureThresholdMinutes: row.early_departure_threshold_minutes,
    overtimeThresholdMinutes: row.overtime_threshold_minutes,
  };
}

/** The caller's own open (clocked-in, not clocked-out) attendance record, if any. */
async function getOpenAttendanceForEmployee(employeeId: string): Promise<AttendanceRecord | null> {
  const { data, error } = await supabase
    .from('attendance_records')
    .select('*')
    .eq('employee_id', employeeId)
    .not('clock_in_at', 'is', null)
    .is('clock_out_at', null)
    .maybeSingle();
  if (error) throw error;
  return data ? toAttendanceRecord(data) : null;
}

async function clockIn(employeeId: string, siteId: string, shiftId?: string): Promise<AttendanceRecord> {
  const { data, error } = await supabase.rpc('clock_in', { p_employee_id: employeeId, p_site_id: siteId, p_shift_id: shiftId });
  if (error) throw error;
  return toAttendanceRecord(data);
}

async function clockOut(attendanceRecordId: string): Promise<AttendanceRecord> {
  const { data, error } = await supabase.rpc('clock_out', { p_attendance_record_id: attendanceRecordId });
  if (error) throw error;
  return toAttendanceRecord(data);
}

async function startBreak(attendanceRecordId: string): Promise<AttendanceBreak> {
  const { data, error } = await supabase.rpc('start_break', { p_attendance_record_id: attendanceRecordId });
  if (error) throw error;
  return toAttendanceBreak(data);
}

async function endBreak(attendanceRecordId: string): Promise<AttendanceBreak> {
  const { data, error } = await supabase.rpc('end_break', { p_attendance_record_id: attendanceRecordId });
  if (error) throw error;
  return toAttendanceBreak(data);
}

async function getOpenBreak(attendanceRecordId: string): Promise<AttendanceBreak | null> {
  const { data, error } = await supabase
    .from('attendance_breaks')
    .select('*')
    .eq('attendance_record_id', attendanceRecordId)
    .is('break_end', null)
    .maybeSingle();
  if (error) throw error;
  return data ? toAttendanceBreak(data) : null;
}

async function requestCorrection(
  attendanceRecordId: string,
  field: AttendanceCorrectionField,
  newValue: string,
  reason: string,
): Promise<AttendanceCorrection> {
  const { data, error } = await supabase.rpc('request_attendance_correction', {
    p_attendance_record_id: attendanceRecordId,
    p_field: field,
    p_new_value: newValue,
    p_reason: reason,
  });
  if (error) throw error;
  return toAttendanceCorrection(data);
}

async function decideCorrection(correctionId: string, approve: boolean, reviewNotes?: string): Promise<AttendanceCorrection> {
  const { data, error } = await supabase.rpc('decide_attendance_correction', {
    p_correction_id: correctionId,
    p_approve: approve,
    p_review_notes: reviewNotes,
  });
  if (error) throw error;
  return toAttendanceCorrection(data);
}

async function getCorrections(tenantId: string, status?: AttendanceCorrection['status']): Promise<AttendanceCorrection[]> {
  let query = supabase.from('attendance_corrections').select('*').eq('tenant_id', tenantId);
  if (status) query = query.eq('status', status);
  const { data, error } = await query.order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toAttendanceCorrection);
}

async function getPolicy(tenantId: string): Promise<AttendancePolicy | null> {
  const { data, error } = await supabase.from('attendance_policies').select('*').eq('tenant_id', tenantId).maybeSingle();
  if (error) throw error;
  return data ? toAttendancePolicy(data) : null;
}

async function upsertPolicy(
  tenantId: string,
  input: { gracePeriodMinutes: number; earlyDepartureThresholdMinutes: number; overtimeThresholdMinutes: number },
): Promise<AttendancePolicy> {
  const { data, error } = await supabase
    .from('attendance_policies')
    .upsert(
      {
        tenant_id: tenantId,
        grace_period_minutes: input.gracePeriodMinutes,
        early_departure_threshold_minutes: input.earlyDepartureThresholdMinutes,
        overtime_threshold_minutes: input.overtimeThresholdMinutes,
      },
      { onConflict: 'tenant_id' },
    )
    .select('*')
    .single();
  if (error) throw error;
  return toAttendancePolicy(data);
}

/** Employees assigned to a site (via site_assignments) — the roster a supervisor marks attendance against. */
async function getSiteRoster(siteId: string): Promise<RosterEmployee[]> {
  const { data, error } = await supabase
    .from('site_assignments')
    .select('employee:employees(id, first_name, last_name, employee_number)')
    .eq('site_id', siteId)
    .is('end_date', null);
  if (error) throw error;
  return data
    .map((row) => row.employee)
    .filter((employee): employee is NonNullable<typeof employee> => employee !== null)
    .map((employee) => ({
      id: employee.id,
      firstName: employee.first_name,
      lastName: employee.last_name,
      employeeNumber: employee.employee_number,
    }));
}

/** Attendance already recorded for a site on a given date (by clock-in date), if any. */
async function getAttendanceForSiteDate(siteId: string, date: string): Promise<AttendanceRecord[]> {
  const { data, error } = await supabase
    .from('attendance_records')
    .select('*')
    .eq('site_id', siteId)
    .gte('created_at', `${date}T00:00:00`)
    .lt('created_at', `${date}T23:59:59.999`);
  if (error) throw error;
  return data.map(toAttendanceRecord);
}

/**
 * Marks attendance for a set of employees at a site in one request — an
 * insert per entry (attendance_records has no natural per-day unique key
 * the way a class register does, since an employee can have more than one
 * shift a day), so re-marking the same day creates additional rows rather
 * than upserting. Good enough for the MVP; a per-shift-scoped call is the
 * more precise path once shift assignment is wired into this UI.
 */
async function saveAttendance(
  tenantId: string,
  siteId: string,
  entries: AttendanceEntry[],
  recordedBy: string,
): Promise<AttendanceRecord[]> {
  const payload: AttendanceRecordInsert[] = entries.map((entry) => ({
    tenant_id: tenantId,
    site_id: siteId,
    employee_id: entry.employeeId,
    status: entry.status,
    recorded_by: recordedBy,
  }));

  const { data, error } = await supabase.from('attendance_records').insert(payload).select('*');
  if (error) throw error;
  return data.map(toAttendanceRecord);
}

/** Status breakdown across a site on a given date — used by dashboard summary panels. */
async function getSiteAttendanceSummary(siteId: string, date: string): Promise<AttendanceStatusCounts> {
  const records = await getAttendanceForSiteDate(siteId, date);
  return tallyStatusCounts(records);
}

/**
 * Every attendance record for the tenant within a date range (inclusive),
 * optionally narrowed to one site — the raw source data for reporting.
 */
async function getAttendanceInRange(
  tenantId: string,
  startDate: string,
  endDate: string,
  siteId?: string,
): Promise<AttendanceRecord[]> {
  const data = await fetchAllRows<AttendanceRecordRow>((from, to) => {
    let query = supabase
      .from('attendance_records')
      .select('*')
      .eq('tenant_id', tenantId)
      .gte('created_at', `${startDate}T00:00:00`)
      .lte('created_at', `${endDate}T23:59:59.999`)
      .range(from, to);
    if (siteId) query = query.eq('site_id', siteId);
    return query;
  });
  return data.map(toAttendanceRecord);
}

/** Every attendance record for one employee, most recent first, optionally capped to the most recent N. */
async function getAttendanceForEmployee(employeeId: string, limit?: number): Promise<AttendanceRecord[]> {
  let query = supabase
    .from('attendance_records')
    .select('*')
    .eq('employee_id', employeeId)
    .order('created_at', { ascending: false });
  if (limit) query = query.limit(limit);

  const { data, error } = await query;
  if (error) throw error;
  return data.map(toAttendanceRecord);
}

export const attendanceService = {
  getSiteRoster,
  getAttendanceForSiteDate,
  saveAttendance,
  getSiteAttendanceSummary,
  getAttendanceInRange,
  getAttendanceForEmployee,
  getOpenAttendanceForEmployee,
  clockIn,
  clockOut,
  startBreak,
  endBreak,
  getOpenBreak,
  requestCorrection,
  decideCorrection,
  getCorrections,
  getPolicy,
  upsertPolicy,
};
