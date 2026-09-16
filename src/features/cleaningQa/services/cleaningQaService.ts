import { supabase } from '@/lib/supabase';
import type { InspectionTemplateRow, InspectionTemplateItemRow, InspectionRow, InspectionResultRow, DefectRow } from '@/lib/dbTypes';
import type {
  InspectionTemplate,
  InspectionTemplateItem,
  Inspection,
  InspectionResult,
  Defect,
  DefectSeverity,
  CreateInspectionInput,
} from '@/features/cleaningQa/types/cleaningQa.types';

function toTemplate(row: InspectionTemplateRow): InspectionTemplate {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    description: row.description,
    category: row.category,
    passThreshold: row.pass_threshold,
    isActive: row.is_active,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toTemplateItem(row: InspectionTemplateItemRow): InspectionTemplateItem {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    templateId: row.template_id,
    areaLabel: row.area_label,
    criterion: row.criterion,
    maxScore: row.max_score,
    weight: row.weight,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
  };
}

export function toInspection(row: InspectionRow): Inspection {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    siteId: row.site_id,
    contractId: row.contract_id,
    variationOrderId: row.variation_order_id,
    templateId: row.template_id,
    inspectorId: row.inspector_id,
    status: row.status,
    scheduledAt: row.scheduled_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    closedAt: row.closed_at,
    overallScore: row.overall_score,
    passed: row.passed,
    notes: row.notes,
    reinspectionOf: row.reinspection_of,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toResult(row: InspectionResultRow): InspectionResult {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    inspectionId: row.inspection_id,
    templateItemId: row.template_item_id,
    score: row.score,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toDefect(row: DefectRow): Defect {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    inspectionId: row.inspection_id,
    inspectionResultId: row.inspection_result_id,
    severity: row.severity,
    description: row.description,
    areaLabel: row.area_label,
    responsibleTeamId: row.responsible_team_id,
    dueDate: row.due_date,
    status: row.status,
    correctiveAction: row.corrective_action,
    resolutionNotes: row.resolution_notes,
    resolvedBy: row.resolved_by,
    resolvedAt: row.resolved_at,
    verifiedBy: row.verified_by,
    verifiedAt: row.verified_at,
    reinspectionId: row.reinspection_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getTemplates(tenantId: string): Promise<InspectionTemplate[]> {
  const { data, error } = await supabase.from('inspection_templates').select('*').eq('tenant_id', tenantId).order('name', { ascending: true });
  if (error) throw error;
  return data.map(toTemplate);
}

async function createTemplate(tenantId: string, name: string, passThreshold: number, description?: string, category?: string): Promise<InspectionTemplate> {
  const { data, error } = await supabase
    .from('inspection_templates')
    .insert({ tenant_id: tenantId, name, pass_threshold: passThreshold, description: description ?? null, category: category ?? null })
    .select('*')
    .single();
  if (error) throw error;
  return toTemplate(data);
}

async function getTemplateItems(templateId: string): Promise<InspectionTemplateItem[]> {
  const { data, error } = await supabase.from('inspection_template_items').select('*').eq('template_id', templateId).order('sort_order', { ascending: true });
  if (error) throw error;
  return data.map(toTemplateItem);
}

async function addTemplateItem(tenantId: string, templateId: string, areaLabel: string, criterion: string, maxScore: number, weight: number): Promise<InspectionTemplateItem> {
  const { data, error } = await supabase
    .from('inspection_template_items')
    .insert({ tenant_id: tenantId, template_id: templateId, area_label: areaLabel, criterion, max_score: maxScore, weight })
    .select('*')
    .single();
  if (error) throw error;
  return toTemplateItem(data);
}

async function getInspections(tenantId: string): Promise<Inspection[]> {
  const { data, error } = await supabase.from('inspections').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toInspection);
}

async function getInspectionsForClient(clientId: string): Promise<Inspection[]> {
  const { data, error } = await supabase.from('inspections').select('*').eq('client_id', clientId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toInspection);
}

async function getInspection(id: string): Promise<Inspection | null> {
  const { data, error } = await supabase.from('inspections').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toInspection(data) : null;
}

async function scheduleInspection(tenantId: string, input: CreateInspectionInput): Promise<Inspection> {
  const { data, error } = await supabase
    .from('inspections')
    .insert({
      tenant_id: tenantId,
      client_id: input.clientId,
      site_id: input.siteId,
      contract_id: input.contractId ?? null,
      template_id: input.templateId,
      scheduled_at: input.scheduledAt ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toInspection(data);
}

async function startInspection(id: string): Promise<Inspection> {
  const { data, error } = await supabase.rpc('start_inspection', { p_inspection_id: id });
  if (error) throw error;
  return toInspection(data);
}

async function submitResult(inspectionId: string, templateItemId: string, score: number, notes?: string): Promise<InspectionResult> {
  const { data, error } = await supabase.rpc('submit_inspection_result', { p_inspection_id: inspectionId, p_template_item_id: templateItemId, p_score: score, p_notes: notes ?? null });
  if (error) throw error;
  return toResult(data);
}

/** The deterministic scoring boundary — overall_score/passed are always server-computed, never client-submitted. */
async function completeInspection(id: string): Promise<Inspection> {
  const { data, error } = await supabase.rpc('complete_inspection', { p_inspection_id: id });
  if (error) throw error;
  return toInspection(data);
}

async function getResults(inspectionId: string): Promise<InspectionResult[]> {
  const { data, error } = await supabase.from('inspection_results').select('*').eq('inspection_id', inspectionId);
  if (error) throw error;
  return data.map(toResult);
}

async function getDefects(inspectionId: string): Promise<Defect[]> {
  const { data, error } = await supabase.from('defects').select('*').eq('inspection_id', inspectionId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toDefect);
}

async function createDefect(inspectionId: string, description: string, severity: DefectSeverity, areaLabel?: string): Promise<Defect> {
  const { data, error } = await supabase.rpc('create_defect', { p_inspection_id: inspectionId, p_description: description, p_severity: severity, p_area_label: areaLabel ?? null });
  if (error) throw error;
  return toDefect(data);
}

async function resolveDefect(defectId: string, resolutionNotes: string, correctiveAction?: string): Promise<Defect> {
  const { data, error } = await supabase.rpc('resolve_defect', { p_defect_id: defectId, p_resolution_notes: resolutionNotes, p_corrective_action: correctiveAction ?? null });
  if (error) throw error;
  return toDefect(data);
}

/** Self-verification is blocked server-side — the resolver cannot also verify their own defect. */
async function verifyDefect(defectId: string): Promise<Defect> {
  const { data, error } = await supabase.rpc('verify_defect', { p_defect_id: defectId });
  if (error) throw error;
  return toDefect(data);
}

/** Refuses to close while any defect remains open/in_progress — a real DB-enforced check. */
async function closeInspection(id: string): Promise<Inspection> {
  const { data, error } = await supabase.rpc('close_inspection', { p_inspection_id: id });
  if (error) throw error;
  return toInspection(data);
}

async function scheduleReinspection(defectId: string, scheduledAt?: string): Promise<Inspection> {
  const { data, error } = await supabase.rpc('schedule_reinspection', { p_defect_id: defectId, p_scheduled_at: scheduledAt ?? null });
  if (error) throw error;
  return toInspection(data);
}

export const cleaningQaService = {
  getTemplates,
  createTemplate,
  getTemplateItems,
  addTemplateItem,
  getInspections,
  getInspectionsForClient,
  getInspection,
  scheduleInspection,
  startInspection,
  submitResult,
  completeInspection,
  getResults,
  getDefects,
  createDefect,
  resolveDefect,
  verifyDefect,
  closeInspection,
  scheduleReinspection,
};
