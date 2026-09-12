import { supabase } from '@/lib/supabase';
import type { AssetRow, AssetStatusEnum } from '@/lib/dbTypes';
import type { Asset } from '@/features/assets/types/assets.types';

function toAsset(row: AssetRow): Asset {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    assetNumber: row.asset_number,
    name: row.name,
    category: row.category,
    serialNumber: row.serial_number,
    siteId: row.site_id,
    custodianEmployeeId: row.custodian_employee_id,
    status: row.status,
    condition: row.condition,
    acquisitionDate: row.acquisition_date,
    acquisitionCost: row.acquisition_cost,
    notes: row.notes,
  };
}

async function getAssets(tenantId: string): Promise<Asset[]> {
  const { data, error } = await supabase.from('assets').select('*').eq('tenant_id', tenantId).order('asset_number', { ascending: true });
  if (error) throw error;
  return data.map(toAsset);
}

async function createAsset(input: { tenantId: string; assetNumber: string; name: string; category: string; siteId?: string; acquisitionCost?: number }): Promise<Asset> {
  const { data, error } = await supabase
    .from('assets')
    .insert({
      tenant_id: input.tenantId,
      asset_number: input.assetNumber,
      name: input.name,
      category: input.category,
      site_id: input.siteId ?? null,
      acquisition_cost: input.acquisitionCost ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toAsset(data);
}

async function assignAsset(assetId: string, employeeId: string, reason?: string): Promise<Asset> {
  const { data, error } = await supabase.rpc('assign_asset', {
    p_asset_id: assetId,
    p_assigned_to_employee_id: employeeId,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  return toAsset(data);
}

async function returnAsset(assetId: string, newStatus: AssetStatusEnum = 'available', condition?: string): Promise<Asset> {
  const { data, error } = await supabase.rpc('return_asset', { p_asset_id: assetId, p_new_status: newStatus, p_condition_at_return: condition ?? null });
  if (error) throw error;
  return toAsset(data);
}

async function transitionAssetStatus(assetId: string, newStatus: AssetStatusEnum): Promise<Asset> {
  const { data, error } = await supabase.rpc('transition_asset_status', { p_asset_id: assetId, p_new_status: newStatus });
  if (error) throw error;
  return toAsset(data);
}

export const assetService = {
  getAssets,
  createAsset,
  assignAsset,
  returnAsset,
  transitionAssetStatus,
};
