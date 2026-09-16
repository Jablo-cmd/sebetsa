import { supabase } from '@/lib/supabase';
import type { SiteAreaRow, SiteAreaInsert, SiteAreaUpdate } from '@/lib/dbTypes';
import type { SiteArea, CreateSiteAreaInput, UpdateSiteAreaInput } from '@/features/orgStructure/types/orgStructure.types';

export function toSiteArea(row: SiteAreaRow): SiteArea {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    name: row.name,
    description: row.description,
    sortOrder: row.sort_order,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** Every area for one site, in display order — a site's area breakdown is small and fits a detail-page section. */
async function getSiteAreas(siteId: string): Promise<SiteArea[]> {
  const { data, error } = await supabase.from('site_areas').select('*').eq('site_id', siteId).order('sort_order', { ascending: true });
  if (error) throw error;
  return data.map(toSiteArea);
}

async function getSiteArea(id: string): Promise<SiteArea | null> {
  const { data, error } = await supabase.from('site_areas').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toSiteArea(data) : null;
}

function toInsertPayload(tenantId: string, input: CreateSiteAreaInput): SiteAreaInsert {
  return {
    tenant_id: tenantId,
    site_id: input.siteId,
    name: input.name,
    description: input.description ?? null,
    sort_order: input.sortOrder ?? 0,
  };
}

async function createSiteArea(tenantId: string, input: CreateSiteAreaInput): Promise<SiteArea> {
  const { data, error } = await supabase.from('site_areas').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toSiteArea(data);
}

async function updateSiteArea(id: string, updates: UpdateSiteAreaInput): Promise<SiteArea> {
  const payload: SiteAreaUpdate = {};
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.description !== undefined) payload.description = updates.description;
  if (updates.sortOrder !== undefined) payload.sort_order = updates.sortOrder;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('site_areas').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toSiteArea(data);
}

async function archiveSiteArea(id: string): Promise<SiteArea> {
  return updateSiteArea(id, { status: 'inactive' });
}

export const siteAreaService = {
  getSiteAreas,
  getSiteArea,
  createSiteArea,
  updateSiteArea,
  archiveSiteArea,
};
