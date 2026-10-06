import { supabase } from '@/lib/supabase';

export type ScopeType = 'region' | 'site' | 'team';

export interface UserScope {
  id: string;
  profileId: string;
  scopeType: ScopeType;
  scopeId: string;
  createdAt: string;
}

/** Roles whose access to site-bound operational records is limited to their assigned scopes. */
export const SCOPED_ROLES = ['regional_manager', 'site_manager', 'supervisor'] as const;

export function isScopedRole(role: string | null | undefined): boolean {
  return SCOPED_ROLES.some((r) => r === role);
}

async function getScopes(profileId: string): Promise<UserScope[]> {
  const { data, error } = await supabase
    .from('user_scopes')
    .select('id, profile_id, scope_type, scope_id, created_at')
    .eq('profile_id', profileId)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return data.map((row) => ({
    id: row.id,
    profileId: row.profile_id,
    scopeType: row.scope_type as ScopeType,
    scopeId: row.scope_id,
    createdAt: row.created_at,
  }));
}

/** Server-side: checks the caller may manage org structure, that the target is in the same tenant, and separation of duties. */
async function grantScope(profileId: string, scopeType: ScopeType, scopeId: string): Promise<void> {
  const { error } = await supabase.rpc('grant_user_scope', { p_profile_id: profileId, p_scope_type: scopeType, p_scope_id: scopeId });
  if (error) throw error;
}

async function revokeScope(scopeRowId: string): Promise<void> {
  const { error } = await supabase.rpc('revoke_user_scope', { p_scope_row_id: scopeRowId });
  if (error) throw error;
}

export const userScopeService = { getScopes, grantScope, revokeScope };
