/**
 * Framework-level and business-module permission catalogue.
 * Extend this union as each new module lands its own permission set.
 */
export type Permission =
  | 'organization.view'
  | 'organization.manage'
  | 'tenant.switch'
  | 'profile.view_own'
  | 'profile.update_own'
  | 'profile.view_any'
  | 'profile.manage_any'
  | 'org_structure.view'
  | 'org_structure.manage'
  | 'employee.view'
  | 'employee.manage'
  | 'scheduling.view'
  | 'scheduling.manage'
  | 'attendance.view'
  | 'attendance.manage'
  | 'leave.view'
  | 'leave.manage'
  | 'leave.approve'
  | 'task.view'
  | 'task.manage'
  | 'reports.view'
  | 'reports.export';
