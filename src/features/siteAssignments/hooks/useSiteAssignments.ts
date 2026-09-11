import { useCallback, useEffect, useState } from 'react';
import { siteAssignmentService } from '@/features/siteAssignments/services/siteAssignmentService';
import type { SiteAssignment, SiteAssignmentsListFilters } from '@/features/siteAssignments/types/siteAssignment.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseSiteAssignmentsResult {
  assignments: SiteAssignment[];
  isLoading: boolean;
  error: string | null;
  filters: SiteAssignmentsListFilters;
  setFilters: (filters: SiteAssignmentsListFilters) => void;
  refetch: () => Promise<void>;
}

export function useSiteAssignments(tenantId: string | undefined): UseSiteAssignmentsResult {
  const [filters, setFilters] = useState<SiteAssignmentsListFilters>({ when: 'current' });
  const [assignments, setAssignments] = useState<SiteAssignment[]>([]);
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
      setAssignments(await siteAssignmentService.getSiteAssignments(tenantId, filters));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site assignments.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters]);

  useEffect(() => {
    void load();
  }, [load]);

  return { assignments, isLoading, error, filters, setFilters, refetch: load };
}

export interface UseSiteAssignmentsForEmployeeResult {
  assignments: SiteAssignment[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

/** Every current site assignment for one employee — for the employee detail page's "Current Sites" section. */
export function useSiteAssignmentsForEmployee(tenantId: string | undefined, employeeId: string | undefined): UseSiteAssignmentsForEmployeeResult {
  const [assignments, setAssignments] = useState<SiteAssignment[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId || !employeeId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setAssignments(await siteAssignmentService.getSiteAssignments(tenantId, { employeeId, when: 'current' }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site assignments.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, employeeId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { assignments, isLoading, error, refetch: load };
}

/** Every current site assignment at one site — for the site detail page's "Current Workforce" section. */
export function useSiteAssignmentsForSite(tenantId: string | undefined, siteId: string | undefined): UseSiteAssignmentsForEmployeeResult {
  const [assignments, setAssignments] = useState<SiteAssignment[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId || !siteId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setAssignments(await siteAssignmentService.getSiteAssignments(tenantId, { siteId, when: 'current' }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site assignments.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, siteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { assignments, isLoading, error, refetch: load };
}
