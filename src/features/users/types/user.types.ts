import type { UserRole } from '@/features/auth/types/auth.types';
import type { Profile, ProfileStatus } from '@/types/profile.types';

/**
 * Roles assignable through the User Management UI. Every non-platform role
 * is assignable here — can_assign_role() (supabase/migrations) is the real
 * enforcement, this is just the UI's offered list.
 */
export const ASSIGNABLE_ROLES = [
  'organization_administrator',
  'operations_manager',
  'regional_manager',
  'site_manager',
  'supervisor',
  'hr_user',
  'employee',
  'client_user',
] as const;
export type AssignableRole = (typeof ASSIGNABLE_ROLES)[number];

export const ASSIGNABLE_ROLE_LABELS: Record<AssignableRole, string> = {
  organization_administrator: 'Organization Administrator',
  operations_manager: 'Operations Manager',
  regional_manager: 'Regional Manager',
  site_manager: 'Site Manager',
  supervisor: 'Supervisor',
  hr_user: 'HR User',
  employee: 'Employee',
  client_user: 'Client User',
};

export interface CreateUserInput {
  firstName: string;
  lastName: string;
  email: string;
  phone?: string | null;
  role: AssignableRole;
  /** Only ever set by the onboarding wizard — see userService.createUser's own doc comment. */
  tenantId?: string;
}

export interface CreateUserResult {
  userId: string;
  temporaryPassword: string;
}

export interface UsersListFilters {
  search?: string;
  role?: UserRole;
  status?: ProfileStatus;
}

export interface UsersListPage {
  users: Profile[];
  totalCount: number;
  page: number;
  pageSize: number;
}
