import { useCallback, useEffect, useState } from 'react';
import { quoteService } from '@/features/quotes/services/quoteService';
import type { Quote, QuoteLineItem, QuotesListFilters } from '@/features/quotes/types/quote.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PAGE_SIZE = 20;

export interface UseQuotesListResult {
  quotes: Quote[];
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  error: string | null;
  filters: QuotesListFilters;
  setFilters: (filters: QuotesListFilters) => void;
  setPage: (page: number) => void;
  refetch: () => Promise<void>;
}

export function useQuotesList(tenantId: string | undefined): UseQuotesListResult {
  const [filters, setFiltersState] = useState<QuotesListFilters>({});
  const [page, setPage] = useState(1);
  const [quotes, setQuotes] = useState<Quote[]>([]);
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
      const result = await quoteService.getQuotes(tenantId, filters, page, PAGE_SIZE);
      setQuotes(result.quotes);
      setTotalCount(result.totalCount);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load quotes.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const setFilters = useCallback((next: QuotesListFilters) => {
    setFiltersState(next);
    setPage(1);
  }, []);

  return { quotes, totalCount, page, pageSize: PAGE_SIZE, isLoading, error, filters, setFilters, setPage, refetch: load };
}

export interface UseQuoteResult {
  quote: Quote | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useQuote(quoteId: string | undefined): UseQuoteResult {
  const [quote, setQuote] = useState<Quote | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!quoteId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setQuote(await quoteService.getQuote(quoteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the quote.'));
    } finally {
      setIsLoading(false);
    }
  }, [quoteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { quote, isLoading, error, refetch: load };
}

export interface UseQuoteLineItemsResult {
  lineItems: QuoteLineItem[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useQuoteLineItems(quoteId: string | undefined): UseQuoteLineItemsResult {
  const [lineItems, setLineItems] = useState<QuoteLineItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!quoteId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setLineItems(await quoteService.getLineItems(quoteId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the quote line items.'));
    } finally {
      setIsLoading(false);
    }
  }, [quoteId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { lineItems, isLoading, error, refetch: load };
}
