import type { UserRole } from '@/features/auth/types/auth.types';

/**
 * Roles that must complete MFA. This MUST match `public.mfa_roles()` in the
 * database (migration 20261008090000_mfa_enforcement.sql): the database is the
 * enforcement point — for these roles every tenant-scoped read, write and RPC
 * is refused unless the session is aal2 — and this list only decides how the
 * UI reacts (force enrolment, or step-up challenge). A test pins the two
 * lists together.
 */
export const MFA_REQUIRED_ROLES: readonly UserRole[] = [
  'platform_administrator',
  'organization_administrator',
  'operations_manager',
  'hr_user',
];

export function isMfaRequiredForRole(role: UserRole | null): boolean {
  return role !== null && MFA_REQUIRED_ROLES.includes(role);
}
