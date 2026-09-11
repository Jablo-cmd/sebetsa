import { supabase } from '@/lib/supabase';
import { profileService, toProfile } from '@/features/profile/services/profileService';
import type { ProfileUpdateInput } from '@/features/profile/services/profileService';
import type { UserRole } from '@/features/auth/types/auth.types';
import type { Profile } from '@/types/profile.types';
import type {
  CreateUserInput,
  CreateUserResult,
  UsersListFilters,
  UsersListPage,
} from '@/features/users/types/user.types';

const DEFAULT_PAGE_SIZE = 20;

/** RLS (`profiles_select_own_or_tenant_or_platform_admin`) scopes this to the caller's own tenant automatically. */
async function getUsers(
  filters: UsersListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<UsersListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('profiles').select('*', { count: 'exact' });

  const term = filters.search?.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.or(`first_name.ilike.%${escaped}%,last_name.ilike.%${escaped}%,email.ilike.%${escaped}%`);
  }
  if (filters.role) query = query.eq('role', filters.role);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error, count } = await query.order('created_at', { ascending: false }).range(from, to);
  if (error) throw error;

  return {
    users: data.map(toProfile),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}

async function getUserById(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle();
  if (error) throw error;
  return data ? toProfile(data) : null;
}

/**
 * Privileged: creates the auth account + profile via the admin_create_user
 * RPC (see supabase/migrations). tenantId is normally omitted — the RPC
 * falls back to the caller's own current_tenant_id(), correct for a
 * tenant-scoped admin provisioning within their own school. A
 * platform-level caller has no tenant of their own (current_tenant_id()
 * is always null for them), so provisioning a brand-new school's very
 * first user — nothing else here would create it — requires passing the
 * target school id explicitly; only the onboarding wizard does this
 * (SchoolOnboardingWizardPage), the general Add User modal never does.
 */
async function createUser(input: CreateUserInput): Promise<CreateUserResult> {
  const { data, error } = await supabase.rpc('admin_create_user', {
    p_email: input.email,
    p_first_name: input.firstName,
    p_last_name: input.lastName,
    p_phone: input.phone ?? '',
    p_role: input.role,
    p_tenant_id: input.tenantId ?? undefined,
  });
  if (error) throw error;

  const row = data[0];
  if (!row) throw new Error('User creation did not return the expected result.');
  return { userId: row.user_id, temporaryPassword: row.temporary_password };
}

/** Contact-info edits reuse profileService.updateProfile — the same RLS-gated column set applies whether editing yourself or (as a manager) someone else. */
async function updateUser(userId: string, updates: ProfileUpdateInput): Promise<Profile> {
  return profileService.updateProfile(userId, updates);
}

/** Privileged: the only path that changes `role` — see admin_update_user_role in supabase/migrations. */
async function updateUserRole(userId: string, role: UserRole): Promise<void> {
  const { error } = await supabase.rpc('admin_update_user_role', {
    p_user_id: userId,
    p_new_role: role,
  });
  if (error) throw error;
}

async function deactivateUser(userId: string): Promise<Profile> {
  const { data, error } = await supabase
    .from('profiles')
    .update({ status: 'inactive' })
    .eq('id', userId)
    .select('*')
    .single();
  if (error) throw error;
  return toProfile(data);
}

export const userService = {
  getUsers,
  getUserById,
  createUser,
  updateUser,
  updateUserRole,
  deactivateUser,
};
