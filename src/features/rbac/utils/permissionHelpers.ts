import type { UserRole } from '@/features/auth/types/auth.types';
import type { Permission } from '@/features/rbac/types/permission.types';
import { ROLE_PERMISSIONS } from '@/features/rbac/constants/rolePermissions';

/** Granted to every authenticated user regardless of role — see rolePermissions.ts. */
const BASELINE_PERMISSIONS: readonly Permission[] = ['profile.view_own', 'profile.update_own'];

/**
 * Pure authorization check: does `role` carry `permission`?
 * Assumes the caller already knows the user is authenticated — this
 * function does not perform authentication, only authorization.
 */
export function hasPermission(role: UserRole | null | undefined, permission: Permission): boolean {
  if (BASELINE_PERMISSIONS.includes(permission)) return true;
  if (!role) return false;
  return ROLE_PERMISSIONS[role].includes(permission);
}

export function hasAnyPermission(role: UserRole | null | undefined, permissions: Permission[]): boolean {
  return permissions.some((permission) => hasPermission(role, permission));
}

export function hasAllPermissions(role: UserRole | null | undefined, permissions: Permission[]): boolean {
  return permissions.every((permission) => hasPermission(role, permission));
}

/** Alias for hasPermission — reads better at call sites, e.g. `can(role, 'employee.manage')`. */
export function can(role: UserRole | null | undefined, permission: Permission): boolean {
  return hasPermission(role, permission);
}
