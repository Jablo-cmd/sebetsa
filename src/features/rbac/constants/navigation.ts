import type { ComponentType, SVGProps } from 'react';
import type { UserRole } from '@/features/auth/types/auth.types';
import type { Permission } from '@/features/rbac/types/permission.types';
import { hasAnyPermission } from '@/features/rbac/utils/permissionHelpers';
import {
  BriefcaseIcon,
  BuildingIcon,
  CalendarIcon,
  CheckIcon,
  ChatIcon,
  ClipboardListIcon,
  GearIcon,
  GraduationCapIcon,
  GridIcon,
  LayersIcon,
  UsersIcon,
} from '@/components/ui/icons';

export interface NavItemDef {
  label: string;
  path: string;
  icon: ComponentType<SVGProps<SVGSVGElement>>;
  /**
   * The item renders only if the signed-in role holds at least one of these
   * permissions. Omit for items every authenticated user should see
   * (Dashboard, Notifications, My Profile). There is no "show but disable"
   * path — an item the role cannot use is simply not in the model for that
   * role.
   */
  permission?: Permission | Permission[];
  /** Exact-match active state — for a path that is a prefix of sibling paths. */
  end?: boolean;
}

export interface NavGroupDef {
  label: string;
  items: NavItemDef[];
}

/**
 * The single source of truth for the sidebar. `DashboardSidebar` filters
 * this per role and drops any group left empty — see `resolveNavForRole`.
 * Only modules with a real, routed page are modelled here — leave and tasks
 * still have schema + RLS only (see supabase/migrations) but no UI yet, so
 * they are deliberately absent rather than linking to a page that doesn't
 * exist. Scheduling gained a real UI in Phase G (Schedule, My Schedule,
 * Shift Definitions, Availability).
 */
export const NAV_MODEL: NavGroupDef[] = [
  {
    label: 'Overview',
    items: [{ label: 'Dashboard', path: '/dashboard', icon: GridIcon, end: true }],
  },
  {
    label: 'Organisation',
    items: [
      { label: 'Regions', path: '/regions', icon: LayersIcon, permission: 'org_structure.view', end: true },
      { label: 'Clients', path: '/clients', icon: BuildingIcon, permission: 'org_structure.view', end: true },
      { label: 'Sites', path: '/sites', icon: BuildingIcon, permission: 'org_structure.view', end: true },
      { label: 'Contracts', path: '/contracts', icon: ClipboardListIcon, permission: 'org_structure.view', end: true },
    ],
  },
  {
    label: 'Workforce',
    items: [
      { label: 'Employees', path: '/employees', icon: BriefcaseIcon, permission: 'employee.view', end: true },
      { label: 'Teams', path: '/teams', icon: UsersIcon, permission: 'team.view' },
      { label: 'Departments', path: '/employees/departments', icon: LayersIcon, permission: 'department.view' },
      { label: 'Positions', path: '/employees/positions', icon: LayersIcon, permission: 'position.view' },
      { label: 'Site Assignments', path: '/site-assignments', icon: ClipboardListIcon, permission: 'site_assignment.view' },
      { label: 'Site Operations', path: '/site-operations', icon: BuildingIcon, permission: 'site_assignment.view' },
    ],
  },
  {
    label: 'Operations',
    items: [
      { label: 'Schedule', path: '/schedule', icon: CalendarIcon, permission: 'scheduling.view', end: true },
      { label: 'My Schedule', path: '/schedule/mine', icon: CalendarIcon },
      { label: 'Shift Definitions', path: '/schedule/definitions', icon: ClipboardListIcon, permission: 'scheduling.manage' },
      { label: 'Availability', path: '/schedule/availability', icon: CheckIcon, permission: 'availability.view' },
      { label: 'Attendance', path: '/attendance', icon: CheckIcon, permission: 'attendance.view' },
      { label: 'My Attendance', path: '/attendance/mine', icon: CheckIcon, permission: 'attendance.view', end: true },
      { label: 'Attendance Corrections', path: '/attendance/corrections', icon: ClipboardListIcon, permission: 'attendance.manage' },
      { label: 'My Leave', path: '/leave', icon: CalendarIcon, permission: 'leave.view', end: true },
      {
        label: 'Team Leave',
        path: '/leave/team',
        icon: CalendarIcon,
        // leave.view, same as My Leave and RequirePermission's route guard
        // below — an employee also holds leave.view, so they can reach this
        // link too (it shows their own request read-only, redundant with My
        // Leave but not broken). A narrower gate (e.g. team.view) would hide
        // this from `employee` but RequirePermission would then redirect
        // supervisor (team.view, no leave permission at all) straight to
        // /dashboard on click — a dead nav link, which the Phase H spec
        // explicitly forbids. Matching the route guard exactly guarantees
        // every visible link works, at the cost of one redundant entry for
        // employee/hr_user-tier roles.
        permission: 'leave.view',
      },
      { label: 'Leave Management', path: '/leave/management', icon: ClipboardListIcon, permission: 'leave.approve' },
      { label: 'Leave Configuration', path: '/leave/configuration', icon: GearIcon, permission: 'leave.manage' },
      { label: 'My Tasks', path: '/tasks', icon: ClipboardListIcon, permission: 'task.view', end: true },
      { label: 'Task Management', path: '/tasks/management', icon: ClipboardListIcon, permission: 'task.manage' },
      { label: 'My Documents', path: '/documents', icon: ClipboardListIcon, permission: 'document.view', end: true },
      { label: 'Employee Documents', path: '/documents/manage', icon: ClipboardListIcon, permission: 'document.manage' },
    ],
  },
  {
    label: 'Compliance & Safety',
    items: [
      { label: 'Incidents', path: '/incidents', icon: ClipboardListIcon, permission: 'incident.view', end: true },
      { label: 'Compliance', path: '/compliance', icon: CheckIcon, permission: 'compliance.view', end: true },
    ],
  },
  {
    label: 'Resources',
    items: [
      { label: 'Assets', path: '/assets', icon: BriefcaseIcon, permission: 'asset.view', end: true },
      { label: 'Inventory', path: '/inventory', icon: LayersIcon, permission: 'inventory.view', end: true },
      { label: 'Procurement', path: '/procurement', icon: ClipboardListIcon, permission: 'procurement.view', end: true },
    ],
  },
  {
    label: 'Development',
    items: [
      { label: 'My Development', path: '/development', icon: GraduationCapIcon, permission: 'development.view', end: true },
      { label: 'Workforce Development', path: '/development/manage', icon: GraduationCapIcon, permission: 'development.manage', end: true },
    ],
  },
  {
    label: 'Communication',
    items: [
      { label: 'Notifications', path: '/notifications', icon: ChatIcon, end: true },
      { label: 'Notification Preferences', path: '/notifications/settings', icon: GearIcon },
    ],
  },
  {
    label: 'Administration',
    items: [
      { label: 'Users & Roles', path: '/users', icon: UsersIcon, permission: 'profile.manage_any' },
      { label: 'Organizations', path: '/organizations', icon: BuildingIcon, permission: 'tenant.switch' },
      { label: 'My Profile', path: '/my-profile', icon: UsersIcon },
    ],
  },
];

function itemVisible(role: UserRole | null | undefined, item: NavItemDef): boolean {
  if (!item.permission) return true;
  const perms = Array.isArray(item.permission) ? item.permission : [item.permission];
  return hasAnyPermission(role, perms);
}

/**
 * The role's actual sidebar: every group keeps only the items the role can
 * use, and any group with nothing left is dropped entirely. No disabled
 * rows, no placeholders.
 */
export function resolveNavForRole(role: UserRole | null | undefined): NavGroupDef[] {
  return NAV_MODEL.map((group) => ({
    ...group,
    items: group.items.filter((item) => itemVisible(role, item)),
  })).filter((group) => group.items.length > 0);
}
