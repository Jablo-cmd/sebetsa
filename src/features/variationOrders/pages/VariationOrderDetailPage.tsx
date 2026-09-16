import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { usePermissions } from '@/hooks/usePermissions';
import { useVariationOrder } from '@/features/variationOrders/hooks/useVariationOrders';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { variationOrderService } from '@/features/variationOrders/services/variationOrderService';
import { quoteService } from '@/features/quotes/services/quoteService';
import type { Quote } from '@/features/quotes/types/quote.types';
import type { VariationOrderStatus } from '@/features/variationOrders/types/variationOrder.types';
import { supabase } from '@/lib/supabase';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_TONE: Record<VariationOrderStatus, StatusTone> = {
  draft: 'neutral',
  assessed: 'info',
  quoting: 'info',
  quoted: 'warning',
  approved: 'success',
  rejected: 'danger',
  scheduled: 'info',
  in_progress: 'warning',
  completed: 'success',
  invoiced: 'success',
  cancelled: 'danger',
};

function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

export function VariationOrderDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('variation.manage');
  const { variationOrder, isLoading, error, refetch } = useVariationOrder(id);
  const { client } = useClient(variationOrder?.clientId);

  const [clientQuotes, setClientQuotes] = useState<Quote[]>([]);
  const [linkedQuote, setLinkedQuote] = useState<Quote | null>(null);
  const [selectedQuoteId, setSelectedQuoteId] = useState('');
  const [taskStatus, setTaskStatus] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isActing, setIsActing] = useState(false);

  useEffect(() => {
    if (!variationOrder) return;
    void quoteService.getQuotesForClient(variationOrder.clientId).then(setClientQuotes);
    if (variationOrder.quoteId) {
      void quoteService.getQuote(variationOrder.quoteId).then(setLinkedQuote);
    } else {
      setLinkedQuote(null);
    }
    if (variationOrder.taskId) {
      void supabase
        .from('tasks')
        .select('status')
        .eq('id', variationOrder.taskId)
        .maybeSingle()
        .then(({ data }) => setTaskStatus(data?.status ?? null));
    } else {
      setTaskStatus(null);
    }
  }, [variationOrder]);

  if (isLoading) return <FullScreenSpinner label="Loading variation order…" />;
  if (error) return <FullScreenNotice title="Something went wrong" message={error} />;
  if (!variationOrder) {
    return (
      <FullScreenNotice
        title="Variation order not found"
        message="This variation order doesn't exist, or you don't have access to view it."
        action={
          <Link to="/variation-orders" className="focus-ring self-start rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Variation Orders
          </Link>
        }
      />
    );
  }

  const runAction = async (action: () => Promise<unknown>, failureMessage: string) => {
    setIsActing(true);
    setActionError(null);
    try {
      await action();
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, failureMessage));
    } finally {
      setIsActing(false);
    }
  };

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/variation-orders')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Variation Orders
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{variationOrder.title}</h1>
            <p className="text-sm text-content-secondary">
              {client ? (
                <Link to={`/clients/${client.id}`} className="text-brand-600 hover:underline">
                  {client.name}
                </Link>
              ) : (
                'No client'
              )}
            </p>
          </div>
          <StatusBadge label={variationOrder.status.replace(/_/g, ' ')} tone={STATUS_TONE[variationOrder.status]} />
        </div>

        {variationOrder.description && <p className="mt-4 text-sm text-content-secondary">{variationOrder.description}</p>}
        {variationOrder.reason && (
          <p className="mt-2 text-xs text-content-tertiary">
            <span className="font-medium">Reason:</span> {variationOrder.reason}
          </p>
        )}

        <ErrorAlert message={actionError} />

        {canManage && (
          <div className="mt-4 flex flex-wrap gap-2 border-t border-border pt-4">
            {variationOrder.status === 'assessed' && clientQuotes.length > 0 && (
              <div className="flex items-end gap-2">
                <label className="flex flex-col gap-1 text-sm">
                  Link an existing quote
                  <select
                    value={selectedQuoteId}
                    onChange={(event) => setSelectedQuoteId(event.target.value)}
                    className="focus-ring h-10 rounded-lg border border-border-strong bg-surface-raised px-3"
                  >
                    <option value="">Select a quote…</option>
                    {clientQuotes.map((quote) => (
                      <option key={quote.id} value={quote.id}>
                        {quote.quoteNumber} — {formatCurrency(quote.totalAmount)}
                      </option>
                    ))}
                  </select>
                </label>
                <Button
                  variant="secondary"
                  disabled={!selectedQuoteId}
                  isLoading={isActing}
                  onClick={() => void runAction(() => variationOrderService.linkQuote(variationOrder.id, selectedQuoteId), 'Failed to link this quote.')}
                >
                  Link quote
                </Button>
              </div>
            )}
            {variationOrder.status === 'assessed' && clientQuotes.length === 0 && (
              <p className="text-sm text-content-tertiary">
                No quotes exist for this client yet.{' '}
                <Link to="/quotes" className="text-brand-600 hover:underline">
                  Create one
                </Link>{' '}
                first, then come back to link it.
              </p>
            )}
            {variationOrder.status === 'quoting' && (
              <Button variant="secondary" isLoading={isActing} onClick={() => void runAction(() => variationOrderService.markQuoted(variationOrder.id), 'Failed to mark this variation as quoted.')}>
                Mark quoted (sent to client)
              </Button>
            )}
            {variationOrder.status === 'approved' && (
              <Button variant="secondary" isLoading={isActing} onClick={() => void runAction(() => variationOrderService.scheduleWork(variationOrder.id), 'Failed to schedule the work order.')}>
                Schedule work
              </Button>
            )}
            {variationOrder.status === 'scheduled' && (
              <Button
                variant="secondary"
                isLoading={isActing}
                onClick={() => void runAction(() => variationOrderService.transitionStatus(variationOrder.id, 'in_progress'), 'Failed to mark this variation in progress.')}
              >
                Mark in progress
              </Button>
            )}
            {variationOrder.status === 'in_progress' && (
              <Button
                variant="secondary"
                isLoading={isActing}
                onClick={() => void runAction(() => variationOrderService.transitionStatus(variationOrder.id, 'completed'), 'Failed to mark this variation completed — its linked task must be completed first.')}
              >
                Mark completed
              </Button>
            )}
            {variationOrder.status === 'completed' && (
              <Button
                isLoading={isActing}
                onClick={() =>
                  void runAction(async () => {
                    const invoice = await variationOrderService.createInvoice(variationOrder.id);
                    navigate(`/invoices/${invoice.id}`);
                  }, 'Failed to create an invoice for this variation.')
                }
              >
                Create invoice
              </Button>
            )}
          </div>
        )}

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          {linkedQuote && (
            <div>
              <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Linked quote</dt>
              <dd className="mt-1 text-sm text-content-primary">
                <Link to={`/quotes/${linkedQuote.id}`} className="text-brand-600 hover:underline">
                  {linkedQuote.quoteNumber}
                </Link>{' '}
                — {formatCurrency(linkedQuote.totalAmount)} ({linkedQuote.status})
              </dd>
            </div>
          )}
          {taskStatus && (
            <div>
              <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Work order status</dt>
              <dd className="mt-1 text-sm capitalize text-content-primary">{taskStatus.replace(/_/g, ' ')}</dd>
            </div>
          )}
        </dl>
      </div>
    </div>
  );
}
