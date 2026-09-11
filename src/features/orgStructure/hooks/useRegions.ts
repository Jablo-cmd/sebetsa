import { useCallback, useEffect, useState } from 'react';
import { regionService } from '@/features/orgStructure/services/regionService';
import type { Region } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseRegionsResult {
  regions: Region[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useRegions(tenantId: string | undefined): UseRegionsResult {
  const [regions, setRegions] = useState<Region[]>([]);
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
      setRegions(await regionService.getRegions(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load regions.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { regions, isLoading, error, refetch: load };
}

export interface UseRegionResult {
  region: Region | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useRegion(regionId: string | undefined): UseRegionResult {
  const [region, setRegion] = useState<Region | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!regionId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setRegion(await regionService.getRegion(regionId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load region.'));
    } finally {
      setIsLoading(false);
    }
  }, [regionId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { region, isLoading, error, refetch: load };
}
