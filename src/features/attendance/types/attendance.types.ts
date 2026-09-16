/**
 * Domain types for the Attendance feature. Used only within this feature,
 * so per the type-ownership convention these stay here rather than in the
 * cross-feature src/types/ barrel.
 */

export type AttendanceStatus = 'present' | 'late' | 'absent' | 'excused' | 'unconfirmed';

/**
 * Server-computed only — the frontend never sets this. clock_in()/clock_out()
 * derive it from the site's configured geofence + the raw coordinates/
 * accuracy the device reported; a client claiming "verified" is not a
 * parameter either RPC accepts. See supabase/migrations/20260921090000_gps_field_presence.sql.
 */
export type GpsVerificationStatus =
  | 'verified'
  | 'outside_geofence'
  | 'low_accuracy'
  | 'location_unavailable'
  | 'pending_verification'
  | 'offline_pending'
  | 'manual_review'
  | 'not_applicable';

export interface AttendanceRecord {
  id: string;
  tenantId: string;
  shiftId: string | null;
  siteId: string;
  employeeId: string;
  status: AttendanceStatus;
  clockInAt: string | null;
  clockOutAt: string | null;
  lateMinutes: number | null;
  earlyDepartureMinutes: number | null;
  workedMinutes: number | null;
  overtimeMinutes: number | null;
  notes: string | null;
  gpsVerificationStatus: GpsVerificationStatus;
  createdAt: string;
  updatedAt: string;
}

/** A raw device location read, captured once and passed to clock_in/clock_out — never interpreted client-side. */
export interface DeviceLocation {
  latitude: number;
  longitude: number;
  accuracyMeters: number | null;
  capturedAt: string;
}

export type AttendanceLocationExceptionStatus = 'pending' | 'approved' | 'rejected';

export interface AttendanceLocationException {
  id: string;
  tenantId: string;
  attendanceRecordId: string;
  employeeId: string;
  reason: string;
  status: AttendanceLocationExceptionStatus;
  reviewedBy: string | null;
  reviewedAt: string | null;
  reviewNotes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AttendanceBreak {
  id: string;
  tenantId: string;
  attendanceRecordId: string;
  breakStart: string;
  breakEnd: string | null;
}

export type AttendanceCorrectionField = 'clock_in_at' | 'clock_out_at' | 'status';
export type AttendanceCorrectionStatus = 'pending' | 'approved' | 'rejected';

export interface AttendanceCorrection {
  id: string;
  tenantId: string;
  attendanceRecordId: string;
  field: AttendanceCorrectionField;
  previousValue: string | null;
  newValue: string;
  reason: string;
  status: AttendanceCorrectionStatus;
  requestedBy: string | null;
  reviewedBy: string | null;
  reviewedAt: string | null;
  reviewNotes: string | null;
  createdAt: string;
}

export interface AttendancePolicy {
  id: string;
  tenantId: string;
  gracePeriodMinutes: number;
  earlyDepartureThresholdMinutes: number;
  overtimeThresholdMinutes: number;
}

export interface RosterEmployee {
  id: string;
  firstName: string;
  lastName: string;
  employeeNumber: string;
}

export interface AttendanceEntry {
  employeeId: string;
  status: AttendanceStatus;
}

export interface AttendanceStatusCounts {
  present: number;
  late: number;
  absent: number;
  excused: number;
  unconfirmed: number;
}
