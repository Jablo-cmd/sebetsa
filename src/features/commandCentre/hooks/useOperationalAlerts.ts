import { useCallback, useEffect, useState } from 'react';
import { commandCentreService } from '@/features/commandCentre/services/commandCentreService';
import type { OperationalAlert } from '@/features/commandCentre/types/commandCentre.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseOperationalAlertsResult {
  alerts: OperationalAlert[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useOperationalAlerts(tenantId: string | undefined, status?: OperationalAlert['status']): UseOperationalAlertsResult {
  const [alerts, setAlerts] = useState<OperationalAlert[]>([]);
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
      setAlerts(await commandCentreService.getAlerts(tenantId, status));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load operational alerts.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, status]);

  useEffect(() => {
    void load();
  }, [load]);

  return { alerts, isLoading, error, refetch: load };
}
