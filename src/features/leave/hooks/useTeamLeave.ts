import { useCallback, useEffect, useState } from 'react';
import { leaveService } from '@/features/leave/services/leaveService';
import type { LeaveRequestSummary } from '@/features/leave/types/leave.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseTeamLeaveResult {
  leaveRequests: LeaveRequestSummary[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** Field-projected leave list for read-only viewers (site_manager tier) —
 * see leaveService.getLeaveRequestsSummary for what's deliberately omitted. */
export function useTeamLeave(tenantId: string | undefined): UseTeamLeaveResult {
  const [leaveRequests, setLeaveRequests] = useState<LeaveRequestSummary[]>([]);
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
      setLeaveRequests(await leaveService.getLeaveRequestsSummary(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load team leave.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { leaveRequests, isLoading, error, refetch: load };
}
