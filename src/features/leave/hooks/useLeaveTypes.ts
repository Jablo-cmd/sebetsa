import { useCallback, useEffect, useState } from 'react';
import { leaveTypeService } from '@/features/leave/services/leaveTypeService';
import type { LeaveType } from '@/features/leave/types/leave.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseLeaveTypesResult {
  leaveTypes: LeaveType[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useLeaveTypes(tenantId: string | undefined, includeInactive = false): UseLeaveTypesResult {
  const [leaveTypes, setLeaveTypes] = useState<LeaveType[]>([]);
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
      setLeaveTypes(await leaveTypeService.getLeaveTypes(tenantId, includeInactive));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load leave types.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, includeInactive]);

  useEffect(() => {
    void load();
  }, [load]);

  return { leaveTypes, isLoading, error, refetch: load };
}
