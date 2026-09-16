/**
 * Domain types for workforce intelligence + the AI assistant
 * (supabase/migrations/20260921090500_workforce_intelligence.sql).
 *
 * There is no LLM provider configured anywhere in this repository — no API
 * key, no edge function calling one. The "AI assistant" here is a real,
 * working, permission-aware natural-language *router* onto a fixed set of
 * whitelisted, deterministic SQL tools — every answer is `insightKind:
 * 'rule_based'`, never presented as an inference. `ai_generated` exists in
 * the type/enum as the seam a real LLM integration would use later; nothing
 * in this codebase produces it today. See aiAssistantService.ts.
 */

export type InsightKind = 'rule_based' | 'ai_generated';

export interface AiQueryLogEntry {
  id: string;
  tenantId: string;
  actorProfileId: string;
  queryText: string;
  matchedIntent: string | null;
  responseText: string | null;
  insightKind: InsightKind;
  createdAt: string;
}

export interface UnderstaffedSite {
  siteId: string;
  siteName: string;
  requiredCount: number;
  assignedCount: number;
  shortfall: number;
}

export interface AbsentEmployee {
  employeeId: string;
  employeeName: string;
  siteId: string;
  siteName: string;
  shiftStartsAt: string;
  minutesOverdue: number;
}

export interface ExpiringQualification {
  employeeId: string;
  employeeName: string;
  qualificationName: string;
  expiryDate: string;
  daysRemaining: number;
}

export interface DecliningSlaContract {
  contractId: string;
  contractNumber: string;
  slaName: string;
  latestValue: number;
  targetValue: number;
  targetMet: boolean;
  periodEnd: string;
}

export interface OvertimeSpikeEmployee {
  employeeId: string;
  employeeName: string;
  totalOvertimeMinutes: number;
  recordCount: number;
}

export interface SiteIncidentRanking {
  siteId: string;
  siteName: string;
  incidentCount: number;
  criticalCount: number;
}

export type ShiftRecommendationStatus = 'suggested' | 'accepted' | 'rejected' | 'published';

export interface ShiftRecommendation {
  id: string;
  tenantId: string;
  siteId: string;
  shiftDate: string;
  startsAt: string;
  endsAt: string;
  candidateEmployeeId: string;
  score: number;
  reasons: { factor: string; detail: string }[];
  status: ShiftRecommendationStatus;
  publishedShiftId: string | null;
}
