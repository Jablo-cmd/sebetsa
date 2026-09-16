import { useCallback, useEffect, useState } from 'react';
import { patrolService } from '@/features/patrols/services/patrolService';
import type { PatrolSummary, PatrolRun } from '@/features/patrols/types/patrol.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UsePatrolSummaryResult {
  summary: PatrolSummary | null;
  recentRuns: PatrolRun[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function usePatrolSummary(tenantId: string | undefined): UsePatrolSummaryResult {
  const [summary, setSummary] = useState<PatrolSummary | null>(null);
  const [recentRuns, setRecentRuns] = useState<PatrolRun[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const [summaryResult, runsResult] = await Promise.all([patrolService.getPatrolSummary(tenantId), patrolService.getRecentRuns(tenantId)]);
      setSummary(summaryResult);
      setRecentRuns(runsResult);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load patrol oversight data.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { summary, recentRuns, isLoading, error, refetch: load };
}
