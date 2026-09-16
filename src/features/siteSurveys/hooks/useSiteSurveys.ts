import { useCallback, useEffect, useState } from 'react';
import { siteSurveyService } from '@/features/siteSurveys/services/siteSurveyService';
import type { SiteSurvey, SiteSurveysListFilters } from '@/features/siteSurveys/types/siteSurvey.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PAGE_SIZE = 20;

export interface UseSiteSurveysListResult {
  surveys: SiteSurvey[];
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  error: string | null;
  filters: SiteSurveysListFilters;
  setFilters: (filters: SiteSurveysListFilters) => void;
  setPage: (page: number) => void;
  refetch: () => Promise<void>;
}

export function useSiteSurveysList(tenantId: string | undefined): UseSiteSurveysListResult {
  const [filters, setFiltersState] = useState<SiteSurveysListFilters>({});
  const [page, setPage] = useState(1);
  const [surveys, setSurveys] = useState<SiteSurvey[]>([]);
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
      const result = await siteSurveyService.getSurveys(tenantId, filters, page, PAGE_SIZE);
      setSurveys(result.surveys);
      setTotalCount(result.totalCount);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load site surveys.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const setFilters = useCallback((next: SiteSurveysListFilters) => {
    setFiltersState(next);
    setPage(1);
  }, []);

  return { surveys, totalCount, page, pageSize: PAGE_SIZE, isLoading, error, filters, setFilters, setPage, refetch: load };
}

export interface UseSiteSurveyResult {
  survey: SiteSurvey | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useSiteSurvey(surveyId: string | undefined): UseSiteSurveyResult {
  const [survey, setSurvey] = useState<SiteSurvey | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!surveyId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setSurvey(await siteSurveyService.getSurvey(surveyId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the site survey.'));
    } finally {
      setIsLoading(false);
    }
  }, [surveyId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { survey, isLoading, error, refetch: load };
}
