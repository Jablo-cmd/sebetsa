import { useCallback, useEffect, useState } from 'react';
import { siteAreaService } from '@/features/orgStructure/services/siteAreaService';
import type { SiteArea } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseSiteAreasResult {
  areas: SiteArea[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** Every area for one site, in display order — a site's area breakdown is small and fits a detail-page section. */
export function useSiteAreas(siteId: string | undefined): UseSiteAreasResult {
  const [areas, setAreas] = useState<SiteArea[]>([]);
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
      setAreas(await siteAreaService.getSiteAreas(siteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site areas.'));
    } finally {
      setIsLoading(false);
    }
  }, [siteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { areas, isLoading, error, refetch: load };
}
