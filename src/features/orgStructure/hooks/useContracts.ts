import { useCallback, useEffect, useState } from 'react';
import { contractService } from '@/features/orgStructure/services/contractService';
import type { Contract, ContractsListFilters } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PAGE_SIZE = 20;

export interface UseContractsListResult {
  contracts: Contract[];
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  error: string | null;
  filters: ContractsListFilters;
  setFilters: (filters: ContractsListFilters) => void;
  setPage: (page: number) => void;
  refetch: () => Promise<void>;
}

export function useContractsList(tenantId: string | undefined): UseContractsListResult {
  const [filters, setFiltersState] = useState<ContractsListFilters>({});
  const [page, setPage] = useState(1);
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [totalCount, setTotalCount] = useState(0);
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
      const result = await contractService.getContracts(tenantId, filters, page, PAGE_SIZE);
      setContracts(result.contracts);
      setTotalCount(result.totalCount);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load contracts.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const setFilters = useCallback((next: ContractsListFilters) => {
    setFiltersState(next);
    setPage(1);
  }, []);

  return { contracts, totalCount, page, pageSize: PAGE_SIZE, isLoading, error, filters, setFilters, setPage, refetch: load };
}

export interface UseContractsForClientResult {
  contracts: Contract[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useContractsForClient(clientId: string | undefined): UseContractsForClientResult {
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!clientId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setContracts(await contractService.getContractsForClient(clientId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load contracts.'));
    } finally {
      setIsLoading(false);
    }
  }, [clientId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { contracts, isLoading, error, refetch: load };
}

export function useContractsForSite(siteId: string | undefined): UseContractsForClientResult {
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!siteId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setContracts(await contractService.getContractsForSite(siteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load contracts.'));
    } finally {
      setIsLoading(false);
    }
  }, [siteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { contracts, isLoading, error, refetch: load };
}

export interface UseContractResult {
  contract: Contract | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useContract(contractId: string | undefined): UseContractResult {
  const [contract, setContract] = useState<Contract | null>(null);
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
      setContract(await contractService.getContract(contractId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load contract.'));
    } finally {
      setIsLoading(false);
    }
  }, [contractId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { contract, isLoading, error, refetch: load };
}

export interface UseContractSiteIdsResult {
  siteIds: string[];
  isLoading: boolean;
  error: string | null;
}

export function useContractSiteIds(contractId: string | undefined): UseContractSiteIdsResult {
  const [siteIds, setSiteIds] = useState<string[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!contractId) {
      setIsLoading(false);
      return;
    }
    let cancelled = false;
    setIsLoading(true);
    contractService
      .getContractSiteIds(contractId)
      .then((result) => {
        if (!cancelled) setSiteIds(result);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(getDbErrorMessage(err, 'Failed to load contract sites.'));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [contractId]);

  return { siteIds, isLoading, error };
}
