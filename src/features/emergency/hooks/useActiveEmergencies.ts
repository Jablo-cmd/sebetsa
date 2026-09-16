import { useCallback, useEffect, useState } from 'react';
import { emergencyService } from '@/features/emergency/services/emergencyService';
import type { ActiveEmergency } from '@/features/emergency/types/emergency.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseActiveEmergenciesResult {
  emergencies: ActiveEmergency[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useActiveEmergencies(tenantId: string | undefined): UseActiveEmergenciesResult {
  const [emergencies, setEmergencies] = useState<ActiveEmergency[]>([]);
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
      setEmergencies(await emergencyService.getActiveEmergencies(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load active emergencies.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { emergencies, isLoading, error, refetch: load };
}
