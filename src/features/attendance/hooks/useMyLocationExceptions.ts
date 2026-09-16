import { useCallback, useEffect, useState } from 'react';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import type { AttendanceLocationException } from '@/features/attendance/types/attendance.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseMyLocationExceptionsResult {
  exceptions: AttendanceLocationException[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** The caller's own GPS exception requests and their outcome — the employee-facing half of a supervisor's decision, otherwise invisible once the submission confirmation dismisses. */
export function useMyLocationExceptions(employeeId: string | undefined): UseMyLocationExceptionsResult {
  const [exceptions, setExceptions] = useState<AttendanceLocationException[]>([]);
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
      setExceptions(await attendanceService.getMyLocationExceptions(employeeId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load your GPS exception requests.'));
    } finally {
      setIsLoading(false);
    }
  }, [employeeId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { exceptions, isLoading, error, refetch: load };
}
