import { supabase } from '@/lib/supabase';
import type { SiteRow, SiteInsert, SiteUpdate } from '@/lib/dbTypes';
import type {
  Site,
  CreateSiteInput,
  UpdateSiteInput,
  SitesListFilters,
  SitesListPage,
} from '@/features/orgStructure/types/orgStructure.types';

const DEFAULT_PAGE_SIZE = 20;

export function toSite(row: SiteRow): Site {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    regionId: row.region_id,
    name: row.name,
    address: row.address,
    siteType: row.site_type,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getSites(
  tenantId: string,
  filters: SitesListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<SitesListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('sites').select('*', { count: 'exact' }).eq('tenant_id', tenantId);

  const term = filters.search?.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.or(`name.ilike.%${escaped}%,address.ilike.%${escaped}%`);
  }
  if (filters.clientId) query = query.eq('client_id', filters.clientId);
  if (filters.regionId) query = query.eq('region_id', filters.regionId);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error, count } = await query.order('name', { ascending: true }).range(from, to);
  if (error) throw error;

  return { sites: data.map(toSite), totalCount: count ?? 0, page, pageSize };
}

/** Every site for one client, unpaginated — a client's site list is bounded and fits a detail-page section. */
async function getSitesForClient(clientId: string): Promise<Site[]> {
  const { data, error } = await supabase
    .from('sites')
    .select('*')
    .eq('client_id', clientId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toSite);
}

/** Every site in one region, unpaginated — fits a region detail-page section. */
async function getSitesForRegion(regionId: string): Promise<Site[]> {
  const { data, error } = await supabase
    .from('sites')
    .select('*')
    .eq('region_id', regionId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toSite);
}

/** Every site for the tenant, unpaginated — for the contract form's multi-site picker. */
async function getAllSites(tenantId: string): Promise<Site[]> {
  const { data, error } = await supabase
    .from('sites')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toSite);
}

async function getSite(id: string): Promise<Site | null> {
  const { data, error } = await supabase.from('sites').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toSite(data) : null;
}

function toInsertPayload(tenantId: string, input: CreateSiteInput): SiteInsert {
  return {
    tenant_id: tenantId,
    client_id: input.clientId,
    region_id: input.regionId ?? null,
    name: input.name,
    address: input.address ?? null,
    site_type: input.siteType ?? null,
    status: input.status ?? undefined,
  };
}

async function createSite(tenantId: string, input: CreateSiteInput): Promise<Site> {
  const { data, error } = await supabase.from('sites').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toSite(data);
}

async function updateSite(id: string, updates: UpdateSiteInput): Promise<Site> {
  const payload: SiteUpdate = {};
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.clientId !== undefined) payload.client_id = updates.clientId;
  if (updates.regionId !== undefined) payload.region_id = updates.regionId;
  if (updates.address !== undefined) payload.address = updates.address;
  if (updates.siteType !== undefined) payload.site_type = updates.siteType;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('sites').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toSite(data);
}

async function archiveSite(id: string): Promise<Site> {
  return updateSite(id, { status: 'offboarded' });
}

async function restoreSite(id: string): Promise<Site> {
  return updateSite(id, { status: 'active' });
}

export const siteService = {
  getSites,
  getSitesForClient,
  getSitesForRegion,
  getAllSites,
  getSite,
  createSite,
  updateSite,
  archiveSite,
  restoreSite,
};
