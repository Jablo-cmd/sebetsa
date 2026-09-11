import { useCallback, useEffect, useState } from 'react';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import type { AttendanceRecord, RosterEmployee } from '@/features/attendance/types/attendance.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseAttendanceRosterResult {
  roster: RosterEmployee[];
  existingRecords: AttendanceRecord[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** The site's current roster (site_assignments) plus whatever attendance is already recorded for the given date. */
export function useAttendanceRoster(siteId: string | undefined, date: string): UseAttendanceRosterResult {
  const [roster, setRoster] = useState<RosterEmployee[]>([]);
  const [existingRecords, setExistingRecords] = useState<AttendanceRecord[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!siteId) {
      setRoster([]);
      setExistingRecords([]);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const [rosterResult, recordsResult] = await Promise.all([
        attendanceService.getSiteRoster(siteId),
        attendanceService.getAttendanceForSiteDate(siteId, date),
      ]);
      setRoster(rosterResult);
      setExistingRecords(recordsResult);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the site roster.'));
    } finally {
      setIsLoading(false);
    }
  }, [siteId, date]);

  useEffect(() => {
    void load();
  }, [load]);

  return { roster, existingRecords, isLoading, error, refetch: load };
}
