/**
 * Domain types for the Attendance feature. Used only within this feature,
 * so per the type-ownership convention these stay here rather than in the
 * cross-feature src/types/ barrel.
 */

export type AttendanceStatus = 'present' | 'late' | 'absent' | 'excused' | 'unconfirmed';

export interface AttendanceRecord {
  id: string;
  tenantId: string;
  shiftId: string | null;
  siteId: string;
  employeeId: string;
  status: AttendanceStatus;
  clockInAt: string | null;
  clockOutAt: string | null;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
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
