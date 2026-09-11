import type { UserRole } from '@/features/auth/types/auth.types';

/**
 * Approximate total order over roles for "at least as senior as" checks.
 * Mirrors the operational hierarchy: Organisation > Region > Client > Site >
 * Workforce. Gaps of 5 leave room to insert roles later without
 * renumbering the table.
 */
export const ROLE_RANK: Record<UserRole, number> = {
  platform_administrator: 100,
  organization_administrator: 90,
  operations_manager: 80,
  regional_manager: 70,
  site_manager: 60,
  supervisor: 50,
  hr_user: 45,
  employee: 30,
  client_user: 20,
};
