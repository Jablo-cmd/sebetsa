import { useCallback, useEffect, useState } from 'react';
import { leaveBalanceService } from '@/features/leave/services/leaveBalanceService';
import type { LeaveBalance } from '@/features/leave/types/leave.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseLeaveBalancesResult {
  balances: LeaveBalance[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useLeaveBalances(
  tenantId: string | undefined,
  filters: { employeeId?: string; periodYear?: number } = {},
): UseLeaveBalancesResult {
  const [balances, setBalances] = useState<LeaveBalance[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { employeeId, periodYear } = filters;

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setBalances(await leaveBalanceService.getBalances(tenantId, { employeeId, periodYear }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load leave balances.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, employeeId, periodYear]);

  useEffect(() => {
    void load();
  }, [load]);

  return { balances, isLoading, error, refetch: load };
}
