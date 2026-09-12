import { supabase } from '@/lib/supabase';
import type { ProcurementRequestRow, ProcurementStatusEnum } from '@/lib/dbTypes';
import type { ProcurementRequest } from '@/features/assets/types/assets.types';

function toRequest(row: ProcurementRequestRow): ProcurementRequest {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    requestedBy: row.requested_by,
    siteId: row.site_id,
    itemDescription: row.item_description,
    quantity: row.quantity,
    estimatedCost: row.estimated_cost,
    status: row.status,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    rejectedReason: row.rejected_reason,
    createdAt: row.created_at,
  };
}

async function getRequests(tenantId: string): Promise<ProcurementRequest[]> {
  const { data, error } = await supabase.from('procurement_requests').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toRequest);
}

async function submitRequest(input: { tenantId: string; itemDescription: string; quantity: number; siteId?: string; estimatedCost?: number }): Promise<ProcurementRequest> {
  const { data, error } = await supabase.rpc('submit_procurement_request', {
    p_tenant_id: input.tenantId,
    p_item_description: input.itemDescription,
    p_quantity: input.quantity,
    p_site_id: input.siteId ?? null,
    p_estimated_cost: input.estimatedCost ?? null,
  });
  if (error) throw error;
  return toRequest(data);
}

async function decideRequest(requestId: string, approve: boolean, rejectedReason?: string): Promise<ProcurementRequest> {
  const { data, error } = await supabase.rpc('decide_procurement_request', { p_request_id: requestId, p_approve: approve, p_rejected_reason: rejectedReason ?? null });
  if (error) throw error;
  return toRequest(data);
}

async function advanceRequest(requestId: string, newStatus: ProcurementStatusEnum): Promise<ProcurementRequest> {
  const { data, error } = await supabase.rpc('advance_procurement_request', { p_request_id: requestId, p_new_status: newStatus });
  if (error) throw error;
  return toRequest(data);
}

export const procurementService = {
  getRequests,
  submitRequest,
  decideRequest,
  advanceRequest,
};
