import { useCallback, useEffect, useState } from 'react';
import { variationOrderService } from '@/features/variationOrders/services/variationOrderService';
import type { ServiceRequest, VariationOrder } from '@/features/variationOrders/types/variationOrder.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

function useAsyncList<T>(load: () => Promise<T[]>, deps: unknown[]) {
  const [items, setItems] = useState<T[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      setItems(await load());
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load data.'));
    } finally {
      setIsLoading(false);
    }
  }, deps); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { items, isLoading, error, refetch };
}

export function useServiceRequests(tenantId: string | undefined) {
  const { items, isLoading, error, refetch } = useAsyncList<ServiceRequest>(
    () => (tenantId ? variationOrderService.getServiceRequests(tenantId) : Promise.resolve([])),
    [tenantId],
  );
  return { serviceRequests: items, isLoading, error, refetch };
}

export function useVariationOrdersList(tenantId: string | undefined) {
  const { items, isLoading, error, refetch } = useAsyncList<VariationOrder>(
    () => (tenantId ? variationOrderService.getVariationOrders(tenantId) : Promise.resolve([])),
    [tenantId],
  );
  return { variationOrders: items, isLoading, error, refetch };
}

export function useVariationOrdersForClient(clientId: string | undefined) {
  const { items, isLoading, error, refetch } = useAsyncList<VariationOrder>(
    () => (clientId ? variationOrderService.getVariationOrdersForClient(clientId) : Promise.resolve([])),
    [clientId],
  );
  return { variationOrders: items, isLoading, error, refetch };
}

export function useVariationOrder(id: string | undefined) {
  const [variationOrder, setVariationOrder] = useState<VariationOrder | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!id) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setVariationOrder(await variationOrderService.getVariationOrder(id));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the variation order.'));
    } finally {
      setIsLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { variationOrder, isLoading, error, refetch };
}
