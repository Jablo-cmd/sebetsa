/**
 * The whole "understanding" half of the AI assistant: a fixed, auditable
 * keyword match onto one of the six whitelisted deterministic tools — never
 * a free-form NLU model, never arbitrary SQL. See intelligenceService.ts's
 * own header comment for why (no LLM provider is configured anywhere in
 * this repository). Every intent this can match is one the assistant is
 * actually permitted to call; there is no path from a user's question to
 * anything else.
 */
export type IntentKey = 'understaffed_sites' | 'absent_employees' | 'expiring_qualifications' | 'declining_sla' | 'overtime_spikes' | 'incident_hotspots';

const INTENT_KEYWORDS: Record<IntentKey, string[]> = {
  understaffed_sites: ['understaff', 'short staffed', 'short-staffed', 'coverage gap', 'not enough staff', 'staffing gap', 'who is short'],
  absent_employees: ['absent', 'no show', 'no-show', 'missing', "didn't clock in", 'did not clock in', 'not clocked in', "hasn't arrived"],
  expiring_qualifications: ['expir', 'certification', 'qualification', 'license', 'licence', 'psira', 'credential'],
  declining_sla: ['sla', 'breach', 'contract performance', 'service level'],
  overtime_spikes: ['overtime'],
  incident_hotspots: ['incident', 'hotspot', 'hot spot'],
};

/** Returns the first matching intent, or `null` if the query doesn't match any whitelisted tool. */
export function matchIntent(query: string): IntentKey | null {
  const normalized = query.toLowerCase();
  for (const [intent, keywords] of Object.entries(INTENT_KEYWORDS) as [IntentKey, string[]][]) {
    if (keywords.some((keyword) => normalized.includes(keyword))) return intent;
  }
  return null;
}
