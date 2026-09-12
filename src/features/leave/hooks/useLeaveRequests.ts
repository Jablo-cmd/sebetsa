import { useCallback, useEffect, useState } from 'react';
import { leaveService } from '@/features/leave/services/leaveService';
import type { LeaveRequest } from '@/features/leave/types/leave.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseLeaveRequestsResult {
  leaveRequests: LeaveRequest[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useLeaveRequests(
  tenantId: string | undefined,
  filters: { employeeId?: string; status?: string } = {},
): UseLeaveRequestsResult {
  const [leaveRequests, setLeaveRequests] = useState<LeaveRequest[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { employeeId, status } = filters;

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setLeaveRequests(await leaveService.getLeaveRequests(tenantId, { employeeId, status }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load leave requests.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, employeeId, status]);

  useEffect(() => {
    void load();
  }, [load]);

  return { leaveRequests, isLoading, error, refetch: load };
}
