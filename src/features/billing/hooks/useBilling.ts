import { useCallback, useEffect, useState } from 'react';
import { billingService } from '@/features/billing/services/billingService';
import type { Invoice, InvoiceLine, Payment } from '@/features/billing/types/billing.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function useInvoicesList(tenantId: string | undefined) {
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setInvoices(await billingService.getInvoices(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load invoices.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { invoices, isLoading, error, refetch };
}

export function useInvoicesForClient(clientId: string | undefined) {
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!clientId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setInvoices(await billingService.getInvoicesForClient(clientId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load invoices.'));
    } finally {
      setIsLoading(false);
    }
  }, [clientId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { invoices, isLoading, error, refetch };
}

export function useInvoice(id: string | undefined) {
  const [invoice, setInvoice] = useState<Invoice | null>(null);
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
      setInvoice(await billingService.getInvoice(id));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the invoice.'));
    } finally {
      setIsLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { invoice, isLoading, error, refetch };
}

export function useInvoiceLines(invoiceId: string | undefined) {
  const [lines, setLines] = useState<InvoiceLine[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!invoiceId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      setLines(await billingService.getInvoiceLines(invoiceId));
    } finally {
      setIsLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { lines, isLoading, refetch };
}

export function usePayments(invoiceId: string | undefined) {
  const [payments, setPayments] = useState<Payment[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!invoiceId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      setPayments(await billingService.getPayments(invoiceId));
    } finally {
      setIsLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { payments, isLoading, refetch };
}
