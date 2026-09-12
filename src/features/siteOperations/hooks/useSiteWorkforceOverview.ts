import { useCallback, useEffect, useState } from 'react';
import { siteOperationsService } from '@/features/siteOperations/services/siteOperationsService';
import type { SiteWorkforceOverview } from '@/features/siteOperations/types/siteOperations.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseSiteWorkforceOverviewResult {
  overview: SiteWorkforceOverview | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useSiteWorkforceOverview(tenantId: string | undefined, siteId: string | undefined): UseSiteWorkforceOverviewResult {
  const [overview, setOverview] = useState<SiteWorkforceOverview | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId || !siteId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setOverview(await siteOperationsService.getSiteWorkforceOverview(tenantId, siteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site workforce overview.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, siteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { overview, isLoading, error, refetch: load };
}
