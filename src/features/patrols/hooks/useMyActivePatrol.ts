import { useCallback, useEffect, useState } from 'react';
import { patrolService } from '@/features/patrols/services/patrolService';
import type { PatrolRun, PatrolCheckpointScan } from '@/features/patrols/types/patrol.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseMyActivePatrolResult {
  activeRun: PatrolRun | null;
  scans: PatrolCheckpointScan[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useMyActivePatrol(employeeId: string | undefined): UseMyActivePatrolResult {
  const [activeRun, setActiveRun] = useState<PatrolRun | null>(null);
  const [scans, setScans] = useState<PatrolCheckpointScan[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!employeeId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const run = await patrolService.getMyActiveRun(employeeId);
      setActiveRun(run);
      setScans(run ? await patrolService.getScansForRun(run.id) : []);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load your patrol status.'));
    } finally {
      setIsLoading(false);
    }
  }, [employeeId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { activeRun, scans, isLoading, error, refetch: load };
}
