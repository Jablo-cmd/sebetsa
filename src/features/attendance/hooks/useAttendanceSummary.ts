import { useCallback, useEffect, useState } from 'react';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import type { AttendanceStatusCounts } from '@/features/attendance/types/attendance.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseAttendanceSummaryResult {
  counts: AttendanceStatusCounts | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** Status breakdown for a site on a given date — powers dashboard Attendance Overview panels. */
export function useAttendanceSummary(siteId: string | undefined, date: string): UseAttendanceSummaryResult {
  const [counts, setCounts] = useState<AttendanceStatusCounts | null>(null);
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
      setCounts(await attendanceService.getSiteAttendanceSummary(siteId, date));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load today’s attendance summary.'));
    } finally {
      setIsLoading(false);
    }
  }, [siteId, date]);

  useEffect(() => {
    void load();
  }, [load]);

  return { counts, isLoading, error, refetch: load };
}
