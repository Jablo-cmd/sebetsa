import { useEffect, useRef, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useAuth } from '@/features/auth/context/authContext';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { intelligenceService } from '@/features/intelligence/services/intelligenceService';
import { matchIntent } from '@/features/intelligence/utils/matchIntent';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { AiQueryLogEntry } from '@/features/intelligence/types/intelligence.types';

const NO_MATCH_RESPONSE =
  "I can only answer questions I have a real, whitelisted tool for: understaffed sites, who's absent right now, expiring qualifications, contracts breaching their SLA, overtime spikes, or site incident hotspots. Try rephrasing around one of those.";

const SUGGESTED_PROMPTS = [
  'Which sites are understaffed?',
  "Who's absent right now?",
  'Any qualifications expiring soon?',
  'Which contracts are breaching SLA?',
  'Who has overtime spikes?',
  'Which sites have the most incidents?',
];

/** Runs the matched intent's whitelisted SQL tool and formats a plain-text answer — never a free-text LLM generation. */
async function answerQuery(tenantId: string, query: string): Promise<{ intent: string | null; text: string }> {
  const intent = matchIntent(query);
  if (!intent) return { intent: null, text: NO_MATCH_RESPONSE };

  switch (intent) {
    case 'understaffed_sites': {
      const rows = await intelligenceService.getUnderstaffedSites(tenantId);
      if (rows.length === 0) return { intent, text: 'No sites are currently understaffed.' };
      return { intent, text: rows.map((r) => `${r.siteName}: short ${r.shortfall} (${r.assignedCount}/${r.requiredCount} assigned)`).join('\n') };
    }
    case 'absent_employees': {
      const rows = await intelligenceService.getEmployeesAbsentNow(tenantId);
      if (rows.length === 0) return { intent, text: 'Nobody is currently absent for a shift that has already started.' };
      return { intent, text: rows.map((r) => `${r.employeeName} at ${r.siteName} — ${r.minutesOverdue} min overdue`).join('\n') };
    }
    case 'expiring_qualifications': {
      const rows = await intelligenceService.getExpiringQualifications(tenantId, 30);
      if (rows.length === 0) return { intent, text: 'No qualifications are expiring in the next 30 days.' };
      return { intent, text: rows.map((r) => `${r.employeeName}: ${r.qualificationName} — ${r.daysRemaining} day(s) left`).join('\n') };
    }
    case 'declining_sla': {
      const rows = await intelligenceService.getDecliningSlaContracts(tenantId);
      if (rows.length === 0) return { intent, text: 'No active contracts are currently breaching their SLA target.' };
      return { intent, text: rows.map((r) => `Contract ${r.contractNumber}: "${r.slaName}" — ${r.latestValue} vs target ${r.targetValue}`).join('\n') };
    }
    case 'overtime_spikes': {
      const rows = await intelligenceService.getOvertimeSpikeEmployees(tenantId);
      if (rows.length === 0) return { intent, text: 'No significant overtime in the last 30 days.' };
      return { intent, text: rows.map((r) => `${r.employeeName}: ${Math.round(r.totalOvertimeMinutes / 60)}h overtime across ${r.recordCount} record(s)`).join('\n') };
    }
    case 'incident_hotspots': {
      const rows = await intelligenceService.getSiteIncidentRanking(tenantId);
      if (rows.length === 0) return { intent, text: 'No incidents recorded in the last 90 days.' };
      return { intent, text: rows.map((r) => `${r.siteName}: ${r.incidentCount} incident(s), ${r.criticalCount} critical`).join('\n') };
    }
  }
}

/**
 * A real, working, permission-aware natural-language router — not a claim
 * that an LLM is answering. Every message routes through exactly one of six
 * whitelisted, deterministic SQL functions (or gets the "I can't answer
 * that" fallback below); every exchange is logged to ai_query_log for
 * audit, insightKind always 'rule_based'. See intelligenceService.ts.
 */
export function AiAssistantPage() {
  const { user } = useAuth();
  const organization = useCurrentOrganization();
  const [entries, setEntries] = useState<AiQueryLogEntry[]>([]);
  const [input, setInput] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!user) return;
    intelligenceService
      .getMyQueryLog(user.id)
      .then(setEntries)
      .catch(() => undefined);
  }, [user]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [entries]);

  if (!organization) return <NoActiveOrganizationNotice resource="the AI assistant" />;

  const handleSend = async () => {
    const query = input.trim();
    if (!query) return;
    setInput('');
    setIsSending(true);
    setError(null);
    try {
      const { intent, text } = await answerQuery(organization.id, query);
      const logged = await intelligenceService.logQuery(query, intent, intent ? [{ tool: intent }] : [], text);
      setEntries((prev) => [...prev, logged]);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to get an answer.'));
    } finally {
      setIsSending(false);
    }
  };

  return (
    <PageContainer width="md">
      <PageHeader title="AI Assistant" description="Ask about staffing, attendance, compliance, SLAs, overtime, or incidents — answered from live data, not a language model." />
      <ErrorAlert message={error} />

      <div className="flex flex-col gap-3 rounded-xl border border-border bg-surface-raised p-4">
        {entries.length === 0 ? (
          <div className="flex flex-wrap gap-2">
            {SUGGESTED_PROMPTS.map((prompt) => (
              <button
                key={prompt}
                type="button"
                onClick={() => setInput(prompt)}
                className="focus-ring rounded-full border border-border-strong px-3 py-1.5 text-xs text-content-secondary hover:bg-surface-sunken"
              >
                {prompt}
              </button>
            ))}
          </div>
        ) : (
          <div className="flex max-h-[28rem] flex-col gap-3 overflow-y-auto">
            {entries.map((entry) => (
              <div key={entry.id} className="flex flex-col gap-1">
                <p className="self-end rounded-lg bg-brand-600 px-3 py-2 text-sm text-white">{entry.queryText}</p>
                <p className="whitespace-pre-line self-start rounded-lg bg-surface-sunken px-3 py-2 text-sm text-content-primary">{entry.responseText}</p>
              </div>
            ))}
            <div ref={bottomRef} />
          </div>
        )}

        <form
          onSubmit={(event) => {
            event.preventDefault();
            void handleSend();
          }}
          className="flex items-end gap-2"
        >
          <TextField
            label="Ask a question"
            placeholder="e.g. Which sites are understaffed?"
            value={input}
            onChange={(event) => setInput(event.target.value)}
            containerClassName="flex-1"
          />
          <Button type="submit" isLoading={isSending} disabled={!input.trim()}>
            Ask
          </Button>
        </form>
      </div>
    </PageContainer>
  );
}
