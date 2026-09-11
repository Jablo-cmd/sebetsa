import { supabase } from '@/lib/supabase';
import type { OrganizationInsert, OrganizationRow } from '@/lib/dbTypes';
import type { Organization, OrganizationStatus } from '@/types/organization.types';

export function toOrganization(row: OrganizationRow): Organization {
  return {
    id: row.id,
    name: row.name,
    registrationNumber: row.registration_number,
    industry: row.industry,
    email: row.email,
    phone: row.phone,
    website: row.website,
    logoUrl: row.logo_url,
    address: row.address,
    timezone: row.timezone,
    currency: row.currency,
    language: row.language,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getOrganizationById(id: string): Promise<Organization | null> {
  const { data, error } = await supabase.from('organizations').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toOrganization(data) : null;
}

/**
 * Organizations visible to the caller for tenant switching. RLS is the
 * actual gate here — a tenant-scoped user gets back only their own
 * organization, a platform admin gets every organization.
 */
async function listAvailableOrganizations(): Promise<Organization[]> {
  const { data, error } = await supabase
    .from('organizations')
    .select('*')
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toOrganization);
}

export interface CreateOrganizationInput {
  name: string;
  industry?: string | null;
  status: OrganizationStatus;
}

/**
 * Onboards a brand-new organization (tenant root). RLS restricts this
 * INSERT to platform admins (organizations_insert_by_platform_admin policy).
 */
async function createOrganization(input: CreateOrganizationInput): Promise<Organization> {
  const payload: OrganizationInsert = {
    name: input.name,
    industry: input.industry ?? null,
    status: input.status,
  };
  const { data, error } = await supabase.from('organizations').insert(payload).select('*').single();
  if (error) throw error;
  return toOrganization(data);
}

export const tenantService = {
  getOrganizationById,
  listAvailableOrganizations,
  createOrganization,
};
