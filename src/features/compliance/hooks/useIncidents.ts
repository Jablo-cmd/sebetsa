import { useCallback, useEffect, useState } from 'react';
import { incidentService } from '@/features/compliance/services/incidentService';
import type { Incident } from '@/features/compliance/types/compliance.types';
import type { IncidentStatusEnum } from '@/lib/dbTypes';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseIncidentsResult {
  incidents: Incident[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useIncidents(tenantId: string | undefined, filters: { status?: IncidentStatusEnum[] } = {}): UseIncidentsResult {
  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { status } = filters;

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setIncidents(await incidentService.getIncidents(tenantId, { status }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load incidents.'));
    } finally {
      setIsLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, status?.join(',')]);

  useEffect(() => {
    void load();
  }, [load]);

  return { incidents, isLoading, error, refetch: load };
}
