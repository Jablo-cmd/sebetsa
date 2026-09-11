import { useCallback, useEffect, useState } from 'react';
import { shiftService } from '@/features/scheduling/services/shiftService';
import type { Shift, ShiftsListFilters } from '@/features/scheduling/types/scheduling.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseShiftsResult {
  shifts: Shift[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/**
 * `filters` is expected to be a stable/memoized object from the caller (see
 * ScheduleWeekGrid/MySchedulePage) — its fields, not its identity, drive
 * refetching.
 */
export function useShifts(tenantId: string | undefined, filters: ShiftsListFilters): UseShiftsResult {
  const [shifts, setShifts] = useState<Shift[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { siteId, employeeId, rangeStart, rangeEnd } = filters;

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setShifts(await shiftService.getShifts(tenantId, { siteId, employeeId, rangeStart, rangeEnd }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the schedule.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, siteId, employeeId, rangeStart, rangeEnd]);

  useEffect(() => {
    void load();
  }, [load]);

  return { shifts, isLoading, error, refetch: load };
}
