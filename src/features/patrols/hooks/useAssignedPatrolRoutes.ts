import { useCallback, useEffect, useState } from 'react';
import { patrolService } from '@/features/patrols/services/patrolService';
import type { PatrolRoute } from '@/features/patrols/types/patrol.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseAssignedPatrolRoutesResult {
  routes: PatrolRoute[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** Active patrol routes at the given site — the routes an employee assigned there may start. */
export function useAssignedPatrolRoutes(siteId: string | null | undefined): UseAssignedPatrolRoutesResult {
  const [routes, setRoutes] = useState<PatrolRoute[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!siteId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setRoutes(await patrolService.getActiveRoutesForSite(siteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load patrol routes for your site.'));
    } finally {
      setIsLoading(false);
    }
  }, [siteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { routes, isLoading, error, refetch: load };
}
