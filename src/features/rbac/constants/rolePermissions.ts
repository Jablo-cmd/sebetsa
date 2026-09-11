import type { UserRole } from '@/features/auth/types/auth.types';
import type { Permission } from '@/features/rbac/types/permission.types';

/**
 * Elevated permissions per role. Every authenticated role additionally
 * carries an implicit baseline of `profile.view_own` / `profile.update_own`
 * (see hasPermission in utils/permissionHelpers.ts), so those two are
 * deliberately omitted here rather than repeated 9 times.
 *
 * Follows the operational hierarchy: Organisation > Region > Client > Site >
 * Workforce. Write access to org structure (regions/clients/sites/contracts)
 * narrows as seniority decreases; `employee` and `client_user` are
 * deliberately minimal — an employee sees their own schedule/attendance/
 * tasks (enforced by RLS + app-level scoping, not by broader permissions
 * here), and client_user is a Phase 2 client-portal role with nothing to
 * grant yet.
 */
export const ROLE_PERMISSIONS: Record<UserRole, readonly Permission[]> = {
  platform_administrator: [
    'organization.view',
    'organization.manage',
    'tenant.switch',
    'profile.view_any',
    'profile.manage_any',
    'org_structure.view',
    'org_structure.manage',
    'employee.view',
    'employee.manage',
    'scheduling.view',
    'scheduling.manage',
    'attendance.view',
    'attendance.manage',
    'leave.view',
    'leave.manage',
    'leave.approve',
    'task.view',
    'task.manage',
    'reports.view',
    'reports.export',
  ],
  organization_administrator: [
    'organization.view',
    'organization.manage',
    'profile.view_any',
    'profile.manage_any',
    'org_structure.view',
    'org_structure.manage',
    'employee.view',
    'employee.manage',
    'scheduling.view',
    'scheduling.manage',
    'attendance.view',
    'attendance.manage',
    'leave.view',
    'leave.manage',
    'leave.approve',
    'task.view',
    'task.manage',
    'reports.view',
    'reports.export',
  ],
  operations_manager: [
    'organization.view',
    'profile.view_any',
    'org_structure.view',
    'org_structure.manage',
    'employee.view',
    'employee.manage',
    'scheduling.view',
    'scheduling.manage',
    'attendance.view',
    'attendance.manage',
    'leave.view',
    'leave.manage',
    'leave.approve',
    'task.view',
    'task.manage',
    'reports.view',
    'reports.export',
  ],
  regional_manager: [
    'organization.view',
    'profile.view_any',
    'org_structure.view',
    'employee.view',
    'scheduling.view',
    'scheduling.manage',
    'attendance.view',
    'attendance.manage',
    'leave.view',
    'leave.approve',
    'task.view',
    'task.manage',
    'reports.view',
  ],
  site_manager: [
    'organization.view',
    'org_structure.view',
    'employee.view',
    'scheduling.view',
    'scheduling.manage',
    'attendance.view',
    'attendance.manage',
    'leave.view',
    'task.view',
    'task.manage',
    'reports.view',
  ],
  supervisor: [
    'organization.view',
    'employee.view',
    'scheduling.view',
    'attendance.view',
    'attendance.manage',
    'task.view',
    'task.manage',
    'reports.view',
  ],
  hr_user: [
    'organization.view',
    'profile.view_any',
    'profile.manage_any',
    'employee.view',
    'employee.manage',
    'leave.view',
    'leave.manage',
    'leave.approve',
    'reports.view',
    'reports.export',
  ],
  employee: ['scheduling.view', 'attendance.view', 'task.view', 'leave.view'],
  client_user: [],
};
