import type { UserRole } from '@/features/auth/types/auth.types';

/**
 * Roles that hold `profile.manage_any` (see rolePermissions.ts) — i.e. can
 * create/manage other users' accounts, a genuine account-takeover-risk
 * capability — plus the top-tier platform-wide admin role. Not every
 * `.manage`-tier role: a site_manager who mis-schedules a shift is a
 * data-quality problem, not the kind of account-takeover risk MFA exists
 * to close.
 *
 * "Required" here is a soft requirement enforced in the UI (a banner
 * nudging enrollment, checked by isMfaRequiredForRole below) — not yet a
 * hard block on app access for the unenrolled.
 */
const MFA_REQUIRED_ROLES: readonly UserRole[] = [
  'platform_administrator',
  'organization_administrator',
  'hr_user',
];

export function isMfaRequiredForRole(role: UserRole | null): boolean {
  return role !== null && MFA_REQUIRED_ROLES.includes(role);
}
