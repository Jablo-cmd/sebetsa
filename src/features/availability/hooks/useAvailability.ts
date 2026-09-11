import { useCallback, useEffect, useState } from 'react';
import { availabilityService } from '@/features/availability/services/availabilityService';
import type { AvailabilityWindow, AvailabilityException } from '@/features/availability/types/availability.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseAvailabilityResult {
  windows: AvailabilityWindow[];
  exceptions: AvailabilityException[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useAvailability(employeeId: string | undefined): UseAvailabilityResult {
  const [windows, setWindows] = useState<AvailabilityWindow[]>([]);
  const [exceptions, setExceptions] = useState<AvailabilityException[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!employeeId) {
      setWindows([]);
      setExceptions([]);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const [windowsResult, exceptionsResult] = await Promise.all([
        availabilityService.getWindows(employeeId),
        availabilityService.getUpcomingExceptions(employeeId),
      ]);
      setWindows(windowsResult);
      setExceptions(exceptionsResult);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load availability.'));
    } finally {
      setIsLoading(false);
    }
  }, [employeeId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { windows, exceptions, isLoading, error, refetch: load };
}
