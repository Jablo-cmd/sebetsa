import { supabase } from '@/lib/supabase';
import type { Json } from '@/lib/database.types';
import type { AiQueryLogRow, ShiftRecommendationRow } from '@/lib/dbTypes';
import type {
  AiQueryLogEntry,
  UnderstaffedSite,
  AbsentEmployee,
  ExpiringQualification,
  DecliningSlaContract,
  OvertimeSpikeEmployee,
  SiteIncidentRanking,
  ShiftRecommendation,
  InsightKind,
} from '@/features/intelligence/types/intelligence.types';

function toAiQueryLogEntry(row: AiQueryLogRow): AiQueryLogEntry {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    actorProfileId: row.actor_profile_id,
    queryText: row.query_text,
    matchedIntent: row.matched_intent,
    responseText: row.response_text,
    insightKind: row.insight_kind,
    createdAt: row.created_at,
  };
}

function toShiftRecommendation(row: ShiftRecommendationRow): ShiftRecommendation {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    shiftDate: row.shift_date,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    candidateEmployeeId: row.candidate_employee_id,
    score: row.score,
    reasons: Array.isArray(row.reasons) ? (row.reasons as ShiftRecommendation['reasons']) : [],
    status: row.status,
    publishedShiftId: row.published_shift_id,
  };
}

async function getUnderstaffedSites(tenantId: string): Promise<UnderstaffedSite[]> {
  const { data, error } = await supabase.rpc('get_understaffed_sites', { p_tenant_id: tenantId });
  if (error) throw error;
  return data.map((row) => ({ siteId: row.site_id, siteName: row.site_name, requiredCount: row.required_count, assignedCount: row.assigned_count, shortfall: row.shortfall }));
}

async function getEmployeesAbsentNow(tenantId: string): Promise<AbsentEmployee[]> {
  const { data, error } = await supabase.rpc('get_employees_absent_now', { p_tenant_id: tenantId });
  if (error) throw error;
  return data.map((row) => ({
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    siteId: row.site_id,
    siteName: row.site_name,
    shiftStartsAt: row.shift_starts_at,
    minutesOverdue: row.minutes_overdue,
  }));
}

async function getExpiringQualifications(tenantId: string, withinDays = 30): Promise<ExpiringQualification[]> {
  const { data, error } = await supabase.rpc('get_expiring_qualifications', { p_tenant_id: tenantId, p_within_days: withinDays });
  if (error) throw error;
  return data.map((row) => ({
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    qualificationName: row.qualification_name,
    expiryDate: row.expiry_date,
    daysRemaining: row.days_remaining,
  }));
}

async function getDecliningSlaContracts(tenantId: string): Promise<DecliningSlaContract[]> {
  const { data, error } = await supabase.rpc('get_declining_sla_contracts', { p_tenant_id: tenantId });
  if (error) throw error;
  return data.map((row) => ({
    contractId: row.contract_id,
    contractNumber: row.contract_number,
    slaName: row.sla_name,
    latestValue: row.latest_value,
    targetValue: row.target_value,
    targetMet: row.target_met,
    periodEnd: row.period_end,
  }));
}

async function getOvertimeSpikeEmployees(tenantId: string, since?: string): Promise<OvertimeSpikeEmployee[]> {
  const { data, error } = await supabase.rpc('get_overtime_spike_employees', { p_tenant_id: tenantId, p_since: since });
  if (error) throw error;
  return data.map((row) => ({ employeeId: row.employee_id, employeeName: row.employee_name, totalOvertimeMinutes: row.total_overtime_minutes, recordCount: row.record_count }));
}

async function getSiteIncidentRanking(tenantId: string, since?: string): Promise<SiteIncidentRanking[]> {
  const { data, error } = await supabase.rpc('get_site_incident_ranking', { p_tenant_id: tenantId, p_since: since });
  if (error) throw error;
  return data.map((row) => ({ siteId: row.site_id, siteName: row.site_name, incidentCount: row.incident_count, criticalCount: row.critical_count }));
}

async function logQuery(queryText: string, matchedIntent: string | null, toolCalls: Json, responseText: string, insightKind: InsightKind = 'rule_based'): Promise<AiQueryLogEntry> {
  const { data, error } = await supabase.rpc('log_ai_query', {
    p_query_text: queryText,
    p_matched_intent: matchedIntent ?? '',
    p_tool_calls: toolCalls,
    p_response_text: responseText,
    p_insight_kind: insightKind,
  });
  if (error) throw error;
  return toAiQueryLogEntry(data);
}

/** The caller's own recent AI-assistant queries — the visible chat history. */
async function getMyQueryLog(actorProfileId: string, limit = 20): Promise<AiQueryLogEntry[]> {
  const { data, error } = await supabase.from('ai_query_log').select('*').eq('actor_profile_id', actorProfileId).order('created_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return data.map(toAiQueryLogEntry).reverse();
}

async function generateShiftRecommendations(siteId: string, shiftDate: string, startsAt: string, endsAt: string): Promise<ShiftRecommendation[]> {
  const { data, error } = await supabase.rpc('generate_shift_recommendations', { p_site_id: siteId, p_shift_date: shiftDate, p_starts_at: startsAt, p_ends_at: endsAt });
  if (error) throw error;
  return data.map(toShiftRecommendation);
}

async function decideShiftRecommendation(recommendationId: string, accept: boolean): Promise<ShiftRecommendation> {
  const { data, error } = await supabase.rpc('decide_shift_recommendation', { p_recommendation_id: recommendationId, p_accept: accept });
  if (error) throw error;
  return toShiftRecommendation(data);
}

async function getSuggestedRecommendations(tenantId: string, limit = 100): Promise<ShiftRecommendation[]> {
  const { data, error } = await supabase
    .from('shift_recommendations')
    .select('*')
    .eq('tenant_id', tenantId)
    .eq('status', 'suggested')
    .order('generated_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data.map(toShiftRecommendation);
}

export const intelligenceService = {
  getUnderstaffedSites,
  getEmployeesAbsentNow,
  getExpiringQualifications,
  getDecliningSlaContracts,
  getOvertimeSpikeEmployees,
  getSiteIncidentRanking,
  logQuery,
  getMyQueryLog,
  generateShiftRecommendations,
  decideShiftRecommendation,
  getSuggestedRecommendations,
};
