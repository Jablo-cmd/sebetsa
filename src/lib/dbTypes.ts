import type { Database } from '@/lib/database.types';

/**
 * Convenience Row/Insert/Update aliases over the generated `Database` type,
 * one per Sebetsa table — service files import from here instead of
 * reaching into `Database['public']['Tables'][...]` directly.
 */
type Tables = Database['public']['Tables'];
type TableRow<T extends keyof Tables> = Tables[T]['Row'];
type TableInsert<T extends keyof Tables> = Tables[T]['Insert'];
type TableUpdate<T extends keyof Tables> = Tables[T]['Update'];

export type OrganizationRow = TableRow<'organizations'>;
export type OrganizationInsert = TableInsert<'organizations'>;
export type OrganizationUpdate = TableUpdate<'organizations'>;

export type ProfileRow = TableRow<'profiles'>;
export type ProfileInsert = TableInsert<'profiles'>;
export type ProfileUpdate = TableUpdate<'profiles'>;

export type RegionRow = TableRow<'regions'>;
export type ClientRow = TableRow<'clients'>;
export type SiteRow = TableRow<'sites'>;
export type ContractRow = TableRow<'contracts'>;

export type DepartmentRow = TableRow<'departments'>;
export type PositionRow = TableRow<'positions'>;
export type EmployeeRow = TableRow<'employees'>;
export type EmployeeInsert = TableInsert<'employees'>;
export type EmployeeUpdate = TableUpdate<'employees'>;
export type TeamRow = TableRow<'teams'>;
export type TeamMemberRow = TableRow<'team_members'>;
export type SiteAssignmentRow = TableRow<'site_assignments'>;

export type ShiftRow = TableRow<'shifts'>;
export type ShiftInsert = TableInsert<'shifts'>;
export type AttendanceRecordRow = TableRow<'attendance_records'>;
export type AttendanceRecordInsert = TableInsert<'attendance_records'>;
export type AttendanceRecordUpdate = TableUpdate<'attendance_records'>;
export type LeaveRequestRow = TableRow<'leave_requests'>;
export type LeaveRequestInsert = TableInsert<'leave_requests'>;
export type LeaveRequestUpdate = TableUpdate<'leave_requests'>;

export type TaskRow = TableRow<'tasks'>;
export type TaskInsert = TableInsert<'tasks'>;
export type TaskUpdate = TableUpdate<'tasks'>;
export type TaskCommentRow = TableRow<'task_comments'>;

export type NotificationRow = TableRow<'notifications'>;
export type AuditLogRow = TableRow<'audit_log'>;

export type UserRoleEnum = Database['public']['Enums']['user_role'];
