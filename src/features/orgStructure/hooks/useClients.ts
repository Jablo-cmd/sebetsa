import { useCallback, useEffect, useState } from 'react';
import { clientService } from '@/features/orgStructure/services/clientService';
import type { Client, ClientsListFilters } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PAGE_SIZE = 20;

export interface UseClientsListResult {
  clients: Client[];
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  error: string | null;
  filters: ClientsListFilters;
  setFilters: (filters: ClientsListFilters) => void;
  setPage: (page: number) => void;
  refetch: () => Promise<void>;
}

export function useClientsList(tenantId: string | undefined): UseClientsListResult {
  const [filters, setFiltersState] = useState<ClientsListFilters>({});
  const [page, setPage] = useState(1);
  const [clients, setClients] = useState<Client[]>([]);
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
      const result = await clientService.getClients(tenantId, filters, page, PAGE_SIZE);
      setClients(result.clients);
      setTotalCount(result.totalCount);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load clients.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const setFilters = useCallback((next: ClientsListFilters) => {
    setFiltersState(next);
    setPage(1);
  }, []);

  return { clients, totalCount, page, pageSize: PAGE_SIZE, isLoading, error, filters, setFilters, setPage, refetch: load };
}

export interface UseAllClientsResult {
  clients: Client[];
  isLoading: boolean;
  error: string | null;
}

/** Unpaginated client list for pickers (site/contract forms). */
export function useAllClients(tenantId: string | undefined): UseAllClientsResult {
  const [clients, setClients] = useState<Client[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    let cancelled = false;
    setIsLoading(true);
    clientService
      .getAllClients(tenantId)
      .then((result) => {
        if (!cancelled) setClients(result);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(getDbErrorMessage(err, 'Failed to load clients.'));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [tenantId]);

  return { clients, isLoading, error };
}

export interface UseClientResult {
  client: Client | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useClient(clientId: string | undefined): UseClientResult {
  const [client, setClient] = useState<Client | null>(null);
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
      setClient(await clientService.getClient(clientId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load client.'));
    } finally {
      setIsLoading(false);
    }
  }, [clientId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { client, isLoading, error, refetch: load };
}
