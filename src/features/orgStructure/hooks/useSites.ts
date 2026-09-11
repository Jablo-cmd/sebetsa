import { useCallback, useEffect, useState } from 'react';
import { siteService } from '@/features/orgStructure/services/siteService';
import type { Site, SitesListFilters } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PAGE_SIZE = 20;

export interface UseSitesListResult {
  sites: Site[];
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  error: string | null;
  filters: SitesListFilters;
  setFilters: (filters: SitesListFilters) => void;
  setPage: (page: number) => void;
  refetch: () => Promise<void>;
}

export function useSitesList(tenantId: string | undefined): UseSitesListResult {
  const [filters, setFiltersState] = useState<SitesListFilters>({});
  const [page, setPage] = useState(1);
  const [sites, setSites] = useState<Site[]>([]);
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
      const result = await siteService.getSites(tenantId, filters, page, PAGE_SIZE);
      setSites(result.sites);
      setTotalCount(result.totalCount);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load sites.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const setFilters = useCallback((next: SitesListFilters) => {
    setFiltersState(next);
    setPage(1);
  }, []);

  return { sites, totalCount, page, pageSize: PAGE_SIZE, isLoading, error, filters, setFilters, setPage, refetch: load };
}

export interface UseSitesForClientResult {
  sites: Site[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useSitesForClient(clientId: string | undefined): UseSitesForClientResult {
  const [sites, setSites] = useState<Site[]>([]);
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
      setSites(await siteService.getSitesForClient(clientId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load sites.'));
    } finally {
      setIsLoading(false);
    }
  }, [clientId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { sites, isLoading, error, refetch: load };
}

export function useSitesForRegion(regionId: string | undefined): UseSitesForClientResult {
  const [sites, setSites] = useState<Site[]>([]);
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
      setSites(await siteService.getSitesForRegion(regionId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load sites.'));
    } finally {
      setIsLoading(false);
    }
  }, [regionId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { sites, isLoading, error, refetch: load };
}

export interface UseAllSitesResult {
  sites: Site[];
  isLoading: boolean;
  error: string | null;
}

/** Unpaginated site list for the contract form's multi-site picker. */
export function useAllSites(tenantId: string | undefined): UseAllSitesResult {
  const [sites, setSites] = useState<Site[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    let cancelled = false;
    setIsLoading(true);
    siteService
      .getAllSites(tenantId)
      .then((result) => {
        if (!cancelled) setSites(result);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(getDbErrorMessage(err, 'Failed to load sites.'));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [tenantId]);

  return { sites, isLoading, error };
}

export interface UseSiteResult {
  site: Site | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useSite(siteId: string | undefined): UseSiteResult {
  const [site, setSite] = useState<Site | null>(null);
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
      setSite(await siteService.getSite(siteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site.'));
    } finally {
      setIsLoading(false);
    }
  }, [siteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { site, isLoading, error, refetch: load };
}
