import { useCallback, useEffect, useState } from 'react';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import type { AttendanceRecord, AttendanceBreak } from '@/features/attendance/types/attendance.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseMyAttendanceResult {
  openRecord: AttendanceRecord | null;
  openBreak: AttendanceBreak | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** The signed-in employee's current open attendance record (if clocked in) and open break (if on break). */
export function useMyAttendance(employeeId: string | undefined): UseMyAttendanceResult {
  const [openRecord, setOpenRecord] = useState<AttendanceRecord | null>(null);
  const [openBreak, setOpenBreak] = useState<AttendanceBreak | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!employeeId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const record = await attendanceService.getOpenAttendanceForEmployee(employeeId);
      setOpenRecord(record);
      setOpenBreak(record ? await attendanceService.getOpenBreak(record.id) : null);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load your attendance status.'));
    } finally {
      setIsLoading(false);
    }
  }, [employeeId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { openRecord, openBreak, isLoading, error, refetch: load };
}
