import { useCallback, useEffect, useState } from 'react';
import { scopeOfWorkService } from '@/features/orgStructure/services/scopeOfWorkService';
import type { ScopeOfWorkItem } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseScopeOfWorkForContractResult {
  items: ScopeOfWorkItem[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** Every scope-of-work item across all of a contract's areas — a contract's scope is bounded and fits a detail-page section. */
export function useScopeOfWorkForContract(contractId: string | undefined): UseScopeOfWorkForContractResult {
  const [items, setItems] = useState<ScopeOfWorkItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!contractId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setItems(await scopeOfWorkService.getScopeOfWorkItemsForContract(contractId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the scope of work.'));
    } finally {
      setIsLoading(false);
    }
  }, [contractId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { items, isLoading, error, refetch: load };
}
