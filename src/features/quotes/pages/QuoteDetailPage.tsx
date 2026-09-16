import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useQuote, useQuoteLineItems } from '@/features/quotes/hooks/useQuotes';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { quoteService } from '@/features/quotes/services/quoteService';
import type { QuoteLineCategory, QuoteStatus } from '@/features/quotes/types/quote.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_TONE: Record<QuoteStatus, StatusTone> = {
  draft: 'neutral',
  sent: 'info',
  viewed: 'info',
  negotiation: 'warning',
  approved: 'success',
  rejected: 'danger',
  expired: 'warning',
  cancelled: 'danger',
};

const NEXT_STATUS_OPTIONS: Record<QuoteStatus, QuoteStatus[]> = {
  draft: ['sent', 'cancelled'],
  sent: ['viewed', 'negotiation', 'expired', 'cancelled'],
  viewed: ['negotiation', 'approved', 'rejected', 'expired', 'cancelled'],
  negotiation: ['sent', 'approved', 'rejected', 'expired', 'cancelled'],
  approved: [],
  rejected: [],
  expired: [],
  cancelled: [],
};

const CATEGORY_OPTIONS: { value: QuoteLineCategory; label: string }[] = [
  { value: 'labour', label: 'Labour' },
  { value: 'consumables', label: 'Consumables' },
  { value: 'equipment', label: 'Equipment' },
  { value: 'transport', label: 'Transport' },
  { value: 'overhead', label: 'Overhead' },
  { value: 'other', label: 'Other' },
];

function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

export function QuoteDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const { quote, isLoading, error, refetch } = useQuote(id);
  const { client } = useClient(quote?.clientId);
  const { lineItems, refetch: refetchLineItems } = useQuoteLineItems(id);
  const organization = useCurrentOrganization();

  const [statusError, setStatusError] = useState<string | null>(null);
  const [isChangingStatus, setIsChangingStatus] = useState(false);
  const [isRecomputing, setIsRecomputing] = useState(false);

  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<QuoteLineCategory>('labour');
  const [quantity, setQuantity] = useState('1');
  const [unitRate, setUnitRate] = useState('');
  const [isAddingLine, setIsAddingLine] = useState(false);
  const [lineError, setLineError] = useState<string | null>(null);

  const [contractNumber, setContractNumber] = useState('');
  const [contractStartDate, setContractStartDate] = useState('');
  const [isConverting, setIsConverting] = useState(false);
  const [convertError, setConvertError] = useState<string | null>(null);

  if (isLoading) return <FullScreenSpinner label="Loading quote…" />;
  if (error) return <FullScreenNotice title="Something went wrong" message={error} />;
  if (!quote) {
    return (
      <FullScreenNotice
        title="Quote not found"
        message="This quote doesn't exist, or you don't have access to view it."
        action={
          <Link to="/quotes" className="focus-ring self-start rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Quotes
          </Link>
        }
      />
    );
  }

  const handleStatusChange = async (status: QuoteStatus) => {
    setStatusError(null);
    setIsChangingStatus(true);
    try {
      await quoteService.updateQuoteStatus(quote.id, status);
      await refetch();
    } catch (err) {
      setStatusError(getDbErrorMessage(err, 'Failed to update the quote status.'));
    } finally {
      setIsChangingStatus(false);
    }
  };

  const handleAddLine = async () => {
    if (!organization || !description.trim() || !unitRate.trim()) return;
    setIsAddingLine(true);
    setLineError(null);
    try {
      await quoteService.addLineItem(organization.id, {
        quoteId: quote.id,
        category,
        description: description.trim(),
        quantity: Number(quantity),
        unitRate: Number(unitRate),
      });
      setDescription('');
      setUnitRate('');
      await refetchLineItems();
      await quoteService.recomputeTotals(quote.id);
      await refetch();
    } catch (err) {
      setLineError(getDbErrorMessage(err, 'Failed to add the line item.'));
    } finally {
      setIsAddingLine(false);
    }
  };

  const handleRecompute = async () => {
    setIsRecomputing(true);
    setLineError(null);
    try {
      await quoteService.recomputeTotals(quote.id);
      await refetch();
    } catch (err) {
      setLineError(getDbErrorMessage(err, 'Failed to recompute totals.'));
    } finally {
      setIsRecomputing(false);
    }
  };

  const handleConvert = async () => {
    if (!contractNumber.trim() || !contractStartDate) return;
    setIsConverting(true);
    setConvertError(null);
    try {
      const contract = await quoteService.convertToContract(quote.id, contractNumber.trim(), contractStartDate);
      await refetch();
      navigate(`/contracts/${contract.id}`);
    } catch (err) {
      setConvertError(getDbErrorMessage(err, 'Failed to convert this quote to a contract.'));
    } finally {
      setIsConverting(false);
    }
  };

  const nextStatuses = NEXT_STATUS_OPTIONS[quote.status];
  const canConvert = quote.status === 'approved' && !quote.convertedToContractId;

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/quotes')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Quotes
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{quote.quoteNumber}</h1>
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
          <StatusBadge label={quote.status} tone={STATUS_TONE[quote.status]} />
        </div>

        <ErrorAlert message={statusError} />

        {canManage && nextStatuses.length > 0 && (
          <div className="mt-4 flex flex-wrap gap-2 border-t border-border pt-4">
            {nextStatuses.map((status) => (
              <Button key={status} variant="secondary" className="h-9 capitalize" onClick={() => void handleStatusChange(status)} isLoading={isChangingStatus}>
                Mark {status}
              </Button>
            ))}
          </div>
        )}

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Subtotal</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(quote.subtotal)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Discount</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(quote.discountAmount)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Tax ({quote.taxRate}%)</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(quote.taxAmount)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Total</dt>
            <dd className="mt-1 text-base font-semibold text-content-primary">{formatCurrency(quote.totalAmount)}</dd>
          </div>
        </dl>

        {quote.convertedToContractId && (
          <p className="mt-4 rounded-lg border border-success-500/30 bg-success-500/10 px-3.5 py-2.5 text-sm font-medium text-success-600">
            Converted to contract.{' '}
            <Link to={`/contracts/${quote.convertedToContractId}`} className="underline">
              View contract
            </Link>
          </p>
        )}
      </div>

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Line items</h2>
          {canManage && (
            <Button variant="ghost" onClick={() => void handleRecompute()} isLoading={isRecomputing}>
              Recompute totals
            </Button>
          )}
        </div>
        <ErrorAlert message={lineError} />
        {lineItems.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No line items yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {lineItems.map((item) => (
              <div key={item.id} className="flex items-center justify-between px-4 py-3 text-sm">
                <div>
                  <span className="font-medium text-content-primary">{item.description}</span>
                  <span className="ml-2 text-xs capitalize text-content-tertiary">{item.category}</span>
                </div>
                <span className="text-content-secondary">
                  {item.quantity} × {formatCurrency(item.unitRate)} = {formatCurrency(item.lineTotal)}
                </span>
              </div>
            ))}
          </div>
        )}
        {canManage && (
          <div className="flex flex-wrap items-end gap-2">
            <TextField label="Description" placeholder="Weekly office cleaning" value={description} onChange={(event) => setDescription(event.target.value)} />
            <label className="flex flex-col gap-1 text-sm">
              Category
              <select value={category} onChange={(event) => setCategory(event.target.value as QuoteLineCategory)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
                {CATEGORY_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>
            <TextField label="Qty" type="number" min={0.01} step="0.01" value={quantity} onChange={(event) => setQuantity(event.target.value)} />
            <TextField label="Unit rate (ZAR)" type="number" min={0} step="0.01" value={unitRate} onChange={(event) => setUnitRate(event.target.value)} />
            <Button variant="secondary" onClick={() => void handleAddLine()} isLoading={isAddingLine} disabled={!description.trim() || !unitRate.trim()}>
              Add line
            </Button>
          </div>
        )}
      </section>

      {canManage && canConvert && (
        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-content-primary">Convert to contract</h2>
          <ErrorAlert message={convertError} />
          <div className="flex flex-wrap items-end gap-2 rounded-card border border-border bg-surface-raised p-4">
            <TextField label="Contract number" placeholder="CTR-2026-001" value={contractNumber} onChange={(event) => setContractNumber(event.target.value)} />
            <TextField label="Start date" type="date" value={contractStartDate} onChange={(event) => setContractStartDate(event.target.value)} />
            <Button onClick={() => void handleConvert()} isLoading={isConverting} disabled={!contractNumber.trim() || !contractStartDate}>
              Convert to contract
            </Button>
          </div>
        </section>
      )}
    </div>
  );
}
