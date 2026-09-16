import { useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useSitesList } from '@/features/attendance/hooks/useSitesList';
import { intelligenceService } from '@/features/intelligence/services/intelligenceService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { ShiftRecommendation } from '@/features/intelligence/types/intelligence.types';

function defaultDate(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  return d.toISOString().slice(0, 10);
}

/**
 * AI-assisted scheduling: GENERATE -> REVIEW -> ACCEPT/REJECT -> PUBLISH.
 * generate_shift_recommendations() only ever writes to shift_recommendations
 * (status 'suggested') — nothing here creates a real `shifts` row until a
 * human explicitly accepts one via decide_shift_recommendation(). The
 * scoring is deterministic (availability + no conflicts + recent hours),
 * never an LLM call.
 */
export function SchedulingRecommendationsPage() {
  const organization = useCurrentOrganization();
  const { sites, isLoading: sitesLoading } = useSitesList(organization?.id);

  const [siteId, setSiteId] = useState('');
  const [shiftDate, setShiftDate] = useState(defaultDate());
  const [startTime, setStartTime] = useState('08:00');
  const [endTime, setEndTime] = useState('16:00');

  const [recommendations, setRecommendations] = useState<ShiftRecommendation[]>([]);
  const [isLoadingExisting, setIsLoadingExisting] = useState(true);
  const [isGenerating, setIsGenerating] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!organization) return;
    intelligenceService
      .getSuggestedRecommendations(organization.id)
      .then(setRecommendations)
      .catch((err) => setError(getDbErrorMessage(err, 'Failed to load scheduling recommendations.')))
      .finally(() => setIsLoadingExisting(false));
  }, [organization]);

  if (!organization) return <NoActiveOrganizationNotice resource="scheduling recommendations" />;

  const handleGenerate = async () => {
    if (!siteId || !shiftDate) return;
    setIsGenerating(true);
    setError(null);
    try {
      const startsAt = new Date(`${shiftDate}T${startTime}:00`).toISOString();
      const endsAt = new Date(`${shiftDate}T${endTime}:00`).toISOString();
      const generated = await intelligenceService.generateShiftRecommendations(siteId, shiftDate, startsAt, endsAt);
      setRecommendations((prev) => [...prev.filter((r) => !(r.siteId === siteId && r.startsAt === startsAt && r.endsAt === endsAt)), ...generated]);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to generate scheduling recommendations.'));
    } finally {
      setIsGenerating(false);
    }
  };

  const handleDecide = async (recommendationId: string, accept: boolean) => {
    setBusyId(recommendationId);
    setError(null);
    try {
      await intelligenceService.decideShiftRecommendation(recommendationId, accept);
      setRecommendations((prev) => prev.filter((r) => r.id !== recommendationId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to record your decision.'));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Scheduling Recommendations" description="Generate candidate shift assignments, then review and accept or reject each one." />
      <ErrorAlert message={error} />

      <div className="rounded-xl border border-border bg-surface-raised p-4">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-4">
          <div>
            <label htmlFor="rec-site" className="mb-1.5 block text-sm font-medium text-content-primary">
              Site
            </label>
            <select
              id="rec-site"
              value={siteId}
              onChange={(event) => setSiteId(event.target.value)}
              disabled={sitesLoading}
              className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
            >
              <option value="">Select a site…</option>
              {sites.map((site) => (
                <option key={site.id} value={site.id}>
                  {site.name}
                </option>
              ))}
            </select>
          </div>
          <TextField label="Date" type="date" value={shiftDate} onChange={(event) => setShiftDate(event.target.value)} />
          <TextField label="Start" type="time" value={startTime} onChange={(event) => setStartTime(event.target.value)} />
          <TextField label="End" type="time" value={endTime} onChange={(event) => setEndTime(event.target.value)} />
        </div>
        <Button className="mt-3 w-full sm:w-auto" onClick={() => void handleGenerate()} isLoading={isGenerating} disabled={!siteId || !shiftDate}>
          Generate recommendations
        </Button>
      </div>

      {isLoadingExisting ? (
        <LoadingBlock label="Loading pending recommendations…" />
      ) : recommendations.length === 0 ? (
        <p className="mt-4 text-sm text-content-secondary">No pending recommendations. Generate some for a site and date above.</p>
      ) : (
        <ul className="mt-4 flex flex-col gap-3">
          {recommendations.map((rec) => (
            <li key={rec.id} className="rounded-xl border border-border bg-surface-raised p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p className="text-sm font-medium text-content-primary">
                    {new Date(rec.startsAt).toLocaleString()} – {new Date(rec.endsAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                  </p>
                  <p className="text-xs text-content-tertiary">Score: {rec.score}</p>
                </div>
                <div className="flex gap-2">
                  <Button variant="secondary" className="h-9" onClick={() => void handleDecide(rec.id, false)} isLoading={busyId === rec.id}>
                    Reject
                  </Button>
                  <Button className="h-9" onClick={() => void handleDecide(rec.id, true)} isLoading={busyId === rec.id}>
                    Accept &amp; publish
                  </Button>
                </div>
              </div>
              {rec.reasons.length > 0 && (
                <ul className="mt-2 list-inside list-disc text-xs text-content-tertiary">
                  {rec.reasons.map((reason, index) => (
                    <li key={index}>{reason.detail}</li>
                  ))}
                </ul>
              )}
            </li>
          ))}
        </ul>
      )}
    </PageContainer>
  );
}
