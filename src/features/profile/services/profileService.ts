import { supabase } from '@/lib/supabase';
import type { ProfileRow, ProfileUpdate } from '@/lib/dbTypes';
import type { Profile } from '@/types/profile.types';

/** Exported so userService (features/users) can reuse it instead of re-declaring its own mapper. */
export function toProfile(row: ProfileRow): Profile {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    firstName: row.first_name,
    lastName: row.last_name,
    email: row.email,
    phone: row.phone,
    avatarUrl: row.avatar_url,
    role: row.role,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getProfileById(userId: string): Promise<Profile | null> {
  const { data, error } = await supabase.from('profiles').select('*').eq('id', userId).maybeSingle();
  if (error) throw error;
  return data ? toProfile(data) : null;
}

export interface ProfileUpdateInput {
  firstName?: string;
  lastName?: string;
  phone?: string | null;
  avatarUrl?: string | null;
}

async function updateProfile(userId: string, updates: ProfileUpdateInput): Promise<Profile> {
  const payload: ProfileUpdate = {};
  if (updates.firstName !== undefined) payload.first_name = updates.firstName;
  if (updates.lastName !== undefined) payload.last_name = updates.lastName;
  if (updates.phone !== undefined) payload.phone = updates.phone;
  if (updates.avatarUrl !== undefined) payload.avatar_url = updates.avatarUrl;

  const { data, error } = await supabase
    .from('profiles')
    .update(payload)
    .eq('id', userId)
    .select('*')
    .single();
  if (error) throw error;
  return toProfile(data);
}

export const profileService = {
  getProfileById,
  updateProfile,
};
