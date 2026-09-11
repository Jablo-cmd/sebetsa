import { useCallback, useEffect, useState } from 'react';
import { shiftDefinitionService } from '@/features/scheduling/services/shiftDefinitionService';
import type { ShiftDefinition } from '@/features/scheduling/types/scheduling.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseShiftDefinitionsResult {
  shiftDefinitions: ShiftDefinition[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useShiftDefinitions(tenantId: string | undefined): UseShiftDefinitionsResult {
  const [shiftDefinitions, setShiftDefinitions] = useState<ShiftDefinition[]>([]);
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
      setShiftDefinitions(await shiftDefinitionService.getShiftDefinitions(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load shift definitions.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { shiftDefinitions, isLoading, error, refetch: load };
}
