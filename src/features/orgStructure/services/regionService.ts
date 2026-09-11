import { supabase } from '@/lib/supabase';
import type { RegionRow, RegionInsert, RegionUpdate } from '@/lib/dbTypes';
import type { Region, CreateRegionInput, UpdateRegionInput } from '@/features/orgStructure/types/orgStructure.types';

export function toRegion(row: RegionRow): Region {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    code: row.code,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getRegions(tenantId: string): Promise<Region[]> {
  const { data, error } = await supabase
    .from('regions')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toRegion);
}

async function getRegion(id: string): Promise<Region | null> {
  const { data, error } = await supabase.from('regions').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toRegion(data) : null;
}

async function createRegion(tenantId: string, input: CreateRegionInput): Promise<Region> {
  const payload: RegionInsert = {
    tenant_id: tenantId,
    name: input.name,
    code: input.code ?? null,
  };
  const { data, error } = await supabase.from('regions').insert(payload).select('*').single();
  if (error) throw error;
  return toRegion(data);
}

async function updateRegion(id: string, updates: UpdateRegionInput): Promise<Region> {
  const payload: RegionUpdate = {};
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.code !== undefined) payload.code = updates.code;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('regions').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toRegion(data);
}

/** Archive rather than hard-delete — a region a client/site still references stays meaningful in history instead of disappearing. RLS permits a DELETE too, but the UI never offers it. */
async function archiveRegion(id: string): Promise<Region> {
  return updateRegion(id, { status: 'inactive' });
}

async function restoreRegion(id: string): Promise<Region> {
  return updateRegion(id, { status: 'active' });
}

export const regionService = {
  getRegions,
  getRegion,
  createRegion,
  updateRegion,
  archiveRegion,
  restoreRegion,
};
