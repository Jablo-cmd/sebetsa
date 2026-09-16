import { supabase } from '@/lib/supabase';
import type { ScopeOfWorkItemRow, ScopeOfWorkItemInsert, ScopeOfWorkItemUpdate, TaskTemplateRow } from '@/lib/dbTypes';
import type {
  ScopeOfWorkItem,
  CreateScopeOfWorkItemInput,
  UpdateScopeOfWorkItemInput,
} from '@/features/orgStructure/types/orgStructure.types';

export function toScopeOfWorkItem(row: ScopeOfWorkItemRow): ScopeOfWorkItem {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    contractId: row.contract_id,
    siteAreaId: row.site_area_id,
    taskName: row.task_name,
    frequency: row.frequency,
    estimatedMinutes: row.estimated_minutes,
    assignedRole: row.assigned_role,
    requiredEquipment: row.required_equipment,
    requiredConsumables: row.required_consumables,
    ppeNotes: row.ppe_notes,
    instructions: row.instructions,
    requiresEvidence: row.requires_evidence,
    priority: row.priority,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** Every scope item for one contract, across all its areas — a contract's scope is bounded and fits a detail-page section. */
async function getScopeOfWorkItemsForContract(contractId: string): Promise<ScopeOfWorkItem[]> {
  const { data, error } = await supabase
    .from('scope_of_work_items')
    .select('*')
    .eq('contract_id', contractId)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return data.map(toScopeOfWorkItem);
}

/** Every scope item for one area, across whichever contract(s) currently cover it. */
async function getScopeOfWorkItemsForArea(siteAreaId: string): Promise<ScopeOfWorkItem[]> {
  const { data, error } = await supabase
    .from('scope_of_work_items')
    .select('*')
    .eq('site_area_id', siteAreaId)
    .order('created_at', { ascending: true });
  if (error) throw error;
  return data.map(toScopeOfWorkItem);
}

function toInsertPayload(tenantId: string, input: CreateScopeOfWorkItemInput): ScopeOfWorkItemInsert {
  return {
    tenant_id: tenantId,
    contract_id: input.contractId,
    site_area_id: input.siteAreaId,
    task_name: input.taskName,
    frequency: input.frequency ?? null,
    estimated_minutes: input.estimatedMinutes ?? null,
    assigned_role: input.assignedRole ?? null,
    required_equipment: input.requiredEquipment ?? null,
    required_consumables: input.requiredConsumables ?? null,
    ppe_notes: input.ppeNotes ?? null,
    instructions: input.instructions ?? null,
    requires_evidence: input.requiresEvidence ?? false,
    priority: input.priority ?? undefined,
  };
}

async function createScopeOfWorkItem(tenantId: string, input: CreateScopeOfWorkItemInput): Promise<ScopeOfWorkItem> {
  const { data, error } = await supabase.from('scope_of_work_items').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toScopeOfWorkItem(data);
}

async function updateScopeOfWorkItem(id: string, updates: UpdateScopeOfWorkItemInput): Promise<ScopeOfWorkItem> {
  const payload: ScopeOfWorkItemUpdate = {};
  if (updates.taskName !== undefined) payload.task_name = updates.taskName;
  if (updates.frequency !== undefined) payload.frequency = updates.frequency;
  if (updates.estimatedMinutes !== undefined) payload.estimated_minutes = updates.estimatedMinutes;
  if (updates.assignedRole !== undefined) payload.assigned_role = updates.assignedRole;
  if (updates.requiredEquipment !== undefined) payload.required_equipment = updates.requiredEquipment;
  if (updates.requiredConsumables !== undefined) payload.required_consumables = updates.requiredConsumables;
  if (updates.ppeNotes !== undefined) payload.ppe_notes = updates.ppeNotes;
  if (updates.instructions !== undefined) payload.instructions = updates.instructions;
  if (updates.requiresEvidence !== undefined) payload.requires_evidence = updates.requiresEvidence;
  if (updates.priority !== undefined) payload.priority = updates.priority;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('scope_of_work_items').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toScopeOfWorkItem(data);
}

async function archiveScopeOfWorkItem(id: string): Promise<ScopeOfWorkItem> {
  return updateScopeOfWorkItem(id, { status: 'inactive' });
}

/** Turns one scope item into a real task_templates row (existing Phase K pipeline) — server-side, one item at a time, never automatic/hidden. */
async function generateTaskTemplate(
  scopeOfWorkItemId: string,
  defaultAssigneeId?: string | null,
  defaultTeamId?: string | null,
): Promise<TaskTemplateRow> {
  const { data, error } = await supabase.rpc('create_task_template_from_scope_item', {
    p_scope_of_work_item_id: scopeOfWorkItemId,
    p_default_assignee_id: defaultAssigneeId ?? null,
    p_default_team_id: defaultTeamId ?? null,
  });
  if (error) throw error;
  return data;
}

export const scopeOfWorkService = {
  getScopeOfWorkItemsForContract,
  getScopeOfWorkItemsForArea,
  createScopeOfWorkItem,
  updateScopeOfWorkItem,
  archiveScopeOfWorkItem,
  generateTaskTemplate,
};
