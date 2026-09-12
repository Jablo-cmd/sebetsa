import { supabase } from '@/lib/supabase';
import type { IncidentRow, IncidentActionRow, IncidentAffectedEmployeeRow, IncidentCategoryEnum, IncidentSeverityEnum, IncidentStatusEnum } from '@/lib/dbTypes';
import type { Incident, IncidentAction } from '@/features/compliance/types/compliance.types';

function toIncident(row: IncidentRow): Incident {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    referenceNumber: row.reference_number,
    siteId: row.site_id,
    contractId: row.contract_id,
    category: row.category,
    severity: row.severity,
    status: row.status,
    occurredAt: row.occurred_at,
    reportedBy: row.reported_by,
    description: row.description,
    investigationNotes: row.investigation_notes,
    correctiveActionSummary: row.corrective_action_summary,
    closedBy: row.closed_by,
    closedAt: row.closed_at,
    createdAt: row.created_at,
  };
}

function toAction(row: IncidentActionRow): IncidentAction {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    incidentId: row.incident_id,
    description: row.description,
    ownerProfileId: row.owner_profile_id,
    dueDate: row.due_date,
    status: row.status,
    completedAt: row.completed_at,
    verifiedBy: row.verified_by,
    verifiedAt: row.verified_at,
  };
}

async function getIncidents(tenantId: string, filters: { status?: IncidentStatusEnum[] } = {}): Promise<Incident[]> {
  let query = supabase.from('incidents').select('*').eq('tenant_id', tenantId);
  if (filters.status?.length) query = query.in('status', filters.status);
  const { data, error } = await query.order('occurred_at', { ascending: false });
  if (error) throw error;
  return data.map(toIncident);
}

async function getIncidentActions(incidentId: string): Promise<IncidentAction[]> {
  const { data, error } = await supabase.from('incident_actions').select('*').eq('incident_id', incidentId).order('due_date', { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data.map(toAction);
}

async function getAffectedEmployees(incidentId: string): Promise<IncidentAffectedEmployeeRow[]> {
  const { data, error } = await supabase.from('incident_affected_employees').select('*').eq('incident_id', incidentId);
  if (error) throw error;
  return data;
}

async function reportIncident(input: {
  tenantId: string;
  category: IncidentCategoryEnum;
  severity: IncidentSeverityEnum;
  occurredAt: string;
  description: string;
  siteId?: string;
  contractId?: string;
}): Promise<Incident> {
  const { data, error } = await supabase.rpc('report_incident', {
    p_tenant_id: input.tenantId,
    p_category: input.category,
    p_severity: input.severity,
    p_occurred_at: input.occurredAt,
    p_description: input.description,
    p_site_id: input.siteId ?? null,
    p_contract_id: input.contractId ?? null,
  });
  if (error) throw error;
  return toIncident(data);
}

async function transitionIncidentStatus(incidentId: string, newStatus: IncidentStatusEnum, notes?: string): Promise<Incident> {
  const { data, error } = await supabase.rpc('transition_incident_status', { p_incident_id: incidentId, p_new_status: newStatus, p_notes: notes ?? null });
  if (error) throw error;
  return toIncident(data);
}

async function linkIncidentEmployee(incidentId: string, employeeId: string, involvement: 'injured' | 'witness' | 'involved' = 'involved') {
  const { data, error } = await supabase.rpc('link_incident_employee', { p_incident_id: incidentId, p_employee_id: employeeId, p_involvement: involvement });
  if (error) throw error;
  return data;
}

async function addIncidentAction(incidentId: string, description: string, ownerProfileId?: string, dueDate?: string): Promise<IncidentAction> {
  const { data, error } = await supabase.rpc('add_incident_action', {
    p_incident_id: incidentId,
    p_description: description,
    p_owner_profile_id: ownerProfileId ?? null,
    p_due_date: dueDate ?? null,
  });
  if (error) throw error;
  return toAction(data);
}

async function completeIncidentAction(actionId: string): Promise<IncidentAction> {
  const { data, error } = await supabase.rpc('complete_incident_action', { p_action_id: actionId });
  if (error) throw error;
  return toAction(data);
}

async function verifyIncidentAction(actionId: string): Promise<IncidentAction> {
  const { data, error } = await supabase.rpc('verify_incident_action', { p_action_id: actionId });
  if (error) throw error;
  return toAction(data);
}

export const incidentService = {
  getIncidents,
  getIncidentActions,
  getAffectedEmployees,
  reportIncident,
  transitionIncidentStatus,
  linkIncidentEmployee,
  addIncidentAction,
  completeIncidentAction,
  verifyIncidentAction,
};
