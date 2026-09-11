import { hasPermission, isAtLeast } from '@/features/rbac';
import type { UserRole } from '@/features/auth/types/auth.types';
import type { AssignableRole } from '@/features/users/types/user.types';

/** Can the actor access user management at all — the existing `profile.manage_any` permission. */
export function canManageUsers(actorRole: UserRole | null): boolean {
  return hasPermission(actorRole, 'profile.manage_any');
}

/**
 * Can the actor manage this SPECIFIC target user? Reuses the existing role
 * hierarchy (isAtLeast) rather than a new one: an actor may only manage
 * users at or below their own seniority — a principal can manage teachers
 * but not another principal or a school owner.
 */
export function canManageUser(actorRole: UserRole | null, targetRole: UserRole | null): boolean {
  if (!canManageUsers(actorRole)) return false;
  if (!targetRole) return true;
  return isAtLeast(actorRole, targetRole);
}

/**
 * Can the actor assign `newRole` to a user currently holding `currentRole`?
 * Mirrors can_assign_role() in supabase/migrations exactly (both enforce
 * the same rule — this one only gates the UI; the SQL function is the
 * real security boundary) — keep them in sync if this ever changes.
 */
export function canAssignRole(
  actorRole: UserRole | null,
  _newRole: AssignableRole,
  _currentRole: UserRole | null,
): boolean {
  // Every AssignableRole already excludes platform_administrator, so any
  // role from that set is fair game for either actor tier.
  return actorRole === 'platform_administrator' || actorRole === 'organization_administrator';
}
