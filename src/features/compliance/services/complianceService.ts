import { supabase } from '@/lib/supabase';
import type { ComplianceRequirementRow, ComplianceRecordRow } from '@/lib/dbTypes';
import type { ComplianceRecord, ComplianceRequirement } from '@/features/compliance/types/compliance.types';

function toRequirement(row: ComplianceRequirementRow): ComplianceRequirement {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    category: row.category,
    description: row.description,
    appliesToScope: row.applies_to_scope as ComplianceRequirement['appliesToScope'],
    recurrenceIntervalDays: row.recurrence_interval_days,
    isActive: row.is_active,
  };
}

function toRecord(row: ComplianceRecordRow): ComplianceRecord {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    requirementId: row.requirement_id,
    siteId: row.site_id,
    clientId: row.client_id,
    contractId: row.contract_id,
    responsibleProfileId: row.responsible_profile_id,
    status: row.status,
    dueDate: row.due_date,
    completedDate: row.completed_date,
    expiryDate: row.expiry_date,
    evidenceStoragePath: row.evidence_storage_path,
    verifiedBy: row.verified_by,
    verifiedAt: row.verified_at,
    notes: row.notes,
  };
}

async function getRequirements(tenantId: string): Promise<ComplianceRequirement[]> {
  const { data, error } = await supabase.from('compliance_requirements').select('*').eq('tenant_id', tenantId).order('name', { ascending: true });
  if (error) throw error;
  return data.map(toRequirement);
}

async function createRequirement(input: { tenantId: string; name: string; category: string; appliesToScope: ComplianceRequirement['appliesToScope']; description?: string; recurrenceIntervalDays?: number }): Promise<ComplianceRequirement> {
  const { data, error } = await supabase
    .from('compliance_requirements')
    .insert({
      tenant_id: input.tenantId,
      name: input.name,
      category: input.category,
      applies_to_scope: input.appliesToScope,
      description: input.description ?? null,
      recurrence_interval_days: input.recurrenceIntervalDays ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toRequirement(data);
}

async function getRecords(tenantId: string): Promise<ComplianceRecord[]> {
  const { data, error } = await supabase.from('compliance_records').select('*').eq('tenant_id', tenantId).order('due_date', { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data.map(toRecord);
}

async function upsertRecord(input: {
  id?: string;
  requirementId: string;
  siteId?: string;
  clientId?: string;
  contractId?: string;
  responsibleProfileId?: string;
  dueDate?: string;
  expiryDate?: string;
  evidenceStoragePath?: string;
  notes?: string;
}): Promise<ComplianceRecord> {
  const { data, error } = await supabase.rpc('upsert_compliance_record', {
    p_id: input.id ?? null,
    p_requirement_id: input.requirementId,
    p_site_id: input.siteId ?? null,
    p_client_id: input.clientId ?? null,
    p_contract_id: input.contractId ?? null,
    p_responsible_profile_id: input.responsibleProfileId ?? null,
    p_due_date: input.dueDate ?? null,
    p_expiry_date: input.expiryDate ?? null,
    p_evidence_storage_path: input.evidenceStoragePath ?? null,
    p_notes: input.notes ?? null,
  });
  if (error) throw error;
  return toRecord(data);
}

async function verifyRecord(id: string, approve: boolean): Promise<ComplianceRecord> {
  const { data, error } = await supabase.rpc('verify_compliance_record', { p_id: id, p_approve: approve });
  if (error) throw error;
  return toRecord(data);
}

export const complianceService = {
  getRequirements,
  createRequirement,
  getRecords,
  upsertRecord,
  verifyRecord,
};
