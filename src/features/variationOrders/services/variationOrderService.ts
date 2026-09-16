import { supabase } from '@/lib/supabase';
import type { ServiceRequestRow, VariationOrderRow } from '@/lib/dbTypes';
import type { ServiceRequest, CreateServiceRequestInput, VariationOrder, VariationOrderStatus } from '@/features/variationOrders/types/variationOrder.types';

export function toServiceRequest(row: ServiceRequestRow): ServiceRequest {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    siteId: row.site_id,
    contractId: row.contract_id,
    requestedBy: row.requested_by,
    requestType: row.request_type,
    description: row.description,
    requestedDate: row.requested_date,
    priority: row.priority,
    status: row.status,
    origin: row.origin,
    resolvedAt: row.resolved_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function toVariationOrder(row: VariationOrderRow): VariationOrder {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    serviceRequestId: row.service_request_id,
    clientId: row.client_id,
    contractId: row.contract_id,
    siteId: row.site_id,
    title: row.title,
    description: row.description,
    reason: row.reason,
    status: row.status,
    quoteId: row.quote_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    taskId: row.task_id,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    completedAt: row.completed_at,
  };
}

async function getServiceRequests(tenantId: string): Promise<ServiceRequest[]> {
  const { data, error } = await supabase.from('service_requests').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toServiceRequest);
}

async function getServiceRequest(id: string): Promise<ServiceRequest | null> {
  const { data, error } = await supabase.from('service_requests').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toServiceRequest(data) : null;
}

/** Internal creation — a client_user instead calls submitServiceRequest(), which server-derives its own client_id. */
async function createServiceRequest(tenantId: string, input: CreateServiceRequestInput): Promise<ServiceRequest> {
  const { data, error } = await supabase
    .from('service_requests')
    .insert({
      tenant_id: tenantId,
      client_id: input.clientId,
      site_id: input.siteId ?? null,
      contract_id: input.contractId ?? null,
      request_type: input.requestType ?? undefined,
      description: input.description,
      requested_date: input.requestedDate ?? null,
      priority: input.priority ?? undefined,
      origin: 'internal',
    })
    .select('*')
    .single();
  if (error) throw error;
  return toServiceRequest(data);
}

/** The only path a client_user can submit a request — client_id/tenant_id are always server-derived, never client-supplied. */
async function submitServiceRequest(input: CreateServiceRequestInput): Promise<ServiceRequest> {
  const { data, error } = await supabase.rpc('submit_service_request', {
    p_request_type: input.requestType ?? 'other',
    p_description: input.description,
    p_site_id: input.siteId ?? null,
    p_contract_id: input.contractId ?? null,
    p_requested_date: input.requestedDate ?? null,
    p_priority: input.priority ?? 'normal',
  });
  if (error) throw error;
  return toServiceRequest(data);
}

async function getVariationOrders(tenantId: string): Promise<VariationOrder[]> {
  const { data, error } = await supabase.from('variation_orders').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toVariationOrder);
}

async function getVariationOrdersForClient(clientId: string): Promise<VariationOrder[]> {
  const { data, error } = await supabase.from('variation_orders').select('*').eq('client_id', clientId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toVariationOrder);
}

async function getVariationOrder(id: string): Promise<VariationOrder | null> {
  const { data, error } = await supabase.from('variation_orders').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toVariationOrder(data) : null;
}

/** Converts an assessed service request into a real variation, reusing the existing quote engine for pricing next. */
async function assessServiceRequest(requestId: string, title: string, description?: string, reason?: string): Promise<VariationOrder> {
  const { data, error } = await supabase.rpc('assess_service_request', {
    p_request_id: requestId,
    p_title: title,
    p_description: description ?? null,
    p_reason: reason ?? null,
  });
  if (error) throw error;
  return toVariationOrder(data);
}

/** Attaches an existing quote (built the normal way) to a variation. */
async function linkQuote(variationId: string, quoteId: string): Promise<VariationOrder> {
  const { data, error } = await supabase.rpc('link_variation_quote', { p_variation_id: variationId, p_quote_id: quoteId });
  if (error) throw error;
  return toVariationOrder(data);
}

async function markQuoted(variationId: string): Promise<VariationOrder> {
  const { data, error } = await supabase.rpc('mark_variation_quoted', { p_variation_id: variationId });
  if (error) throw error;
  return toVariationOrder(data);
}

/** The client-authority boundary — client_id is always server-resolved, never client-supplied. */
async function clientDecideVariation(variationId: string, approve: boolean): Promise<VariationOrder> {
  const { data, error } = await supabase.rpc('client_decide_variation', { p_variation_id: variationId, p_approve: approve });
  if (error) throw error;
  return toVariationOrder(data);
}

/** Creates the real work order (a `tasks` row) once a variation is approved. */
async function scheduleWork(variationId: string, assigneeId?: string | null, dueAt?: string | null): Promise<VariationOrder> {
  const { data, error } = await supabase.rpc('schedule_variation_work', {
    p_variation_id: variationId,
    p_assignee_id: assigneeId ?? null,
    p_due_at: dueAt ?? null,
  });
  if (error) throw error;
  return toVariationOrder(data);
}

async function transitionStatus(variationId: string, status: VariationOrderStatus): Promise<VariationOrder> {
  const { data, error } = await supabase.rpc('transition_variation_status', { p_variation_id: variationId, p_new_status: status });
  if (error) throw error;
  return toVariationOrder(data);
}

/** Bills a completed variation from its own approved quote's line items. */
async function createInvoice(variationId: string): Promise<{ id: string }> {
  const { data, error } = await supabase.rpc('create_variation_invoice', { p_variation_id: variationId });
  if (error) throw error;
  return { id: data.id };
}

export const variationOrderService = {
  getServiceRequests,
  getServiceRequest,
  createServiceRequest,
  submitServiceRequest,
  getVariationOrders,
  getVariationOrdersForClient,
  getVariationOrder,
  assessServiceRequest,
  linkQuote,
  markQuoted,
  clientDecideVariation,
  scheduleWork,
  transitionStatus,
  createInvoice,
};
