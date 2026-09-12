import { supabase } from '@/lib/supabase';
import type { InventoryItemRow, InventoryMovementTypeEnum } from '@/lib/dbTypes';
import type { InventoryItem } from '@/features/assets/types/assets.types';

function toItem(row: InventoryItemRow): InventoryItem {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    sku: row.sku,
    name: row.name,
    category: row.category,
    unit: row.unit,
    reorderThreshold: row.reorder_threshold,
    isActive: row.is_active,
  };
}

async function getItems(tenantId: string): Promise<InventoryItem[]> {
  const { data, error } = await supabase.from('inventory_items').select('*').eq('tenant_id', tenantId).order('name', { ascending: true });
  if (error) throw error;
  return data.map(toItem);
}

async function createItem(input: { tenantId: string; sku: string; name: string; category: string; unit?: string; reorderThreshold?: number }): Promise<InventoryItem> {
  const { data, error } = await supabase
    .from('inventory_items')
    .insert({ tenant_id: input.tenantId, sku: input.sku, name: input.name, category: input.category, unit: input.unit ?? 'each', reorder_threshold: input.reorderThreshold ?? null })
    .select('*')
    .single();
  if (error) throw error;
  return toItem(data);
}

async function getBalance(itemId: string, siteId: string): Promise<number> {
  const { data, error } = await supabase.rpc('get_inventory_balance', { p_item_id: itemId, p_site_id: siteId });
  if (error) throw error;
  return data ?? 0;
}

async function recordMovement(input: { itemId: string; siteId: string; movementType: InventoryMovementTypeEnum; quantity: number; reference?: string }): Promise<void> {
  const { error } = await supabase.rpc('record_inventory_movement', {
    p_item_id: input.itemId,
    p_site_id: input.siteId,
    p_movement_type: input.movementType,
    p_quantity: input.quantity,
    p_reference: input.reference ?? null,
  });
  if (error) throw error;
}

export const inventoryService = {
  getItems,
  createItem,
  getBalance,
  recordMovement,
};
