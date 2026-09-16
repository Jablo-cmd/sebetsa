import { useCallback, useEffect, useState } from 'react';
import { commandCentreService } from '@/features/commandCentre/services/commandCentreService';
import type { CommandCentreSnapshot } from '@/features/commandCentre/types/commandCentre.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseCommandCentreSnapshotResult {
  snapshot: CommandCentreSnapshot | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useCommandCentreSnapshot(tenantId: string | undefined): UseCommandCentreSnapshotResult {
  const [snapshot, setSnapshot] = useState<CommandCentreSnapshot | null>(null);
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
      setSnapshot(await commandCentreService.getSnapshot(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the command centre snapshot.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { snapshot, isLoading, error, refetch: load };
}
