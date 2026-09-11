import { useCallback, useEffect, useState } from 'react';
import { positionService } from '@/features/employees/services/positionService';
import type { Position } from '@/features/employees/types/employee.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UsePositionsResult {
  positions: Position[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function usePositions(tenantId: string | undefined): UsePositionsResult {
  const [positions, setPositions] = useState<Position[]>([]);
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
      setPositions(await positionService.getPositions(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load positions.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { positions, isLoading, error, refetch: load };
}
