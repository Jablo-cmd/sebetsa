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
import { useInvoice, useInvoiceLines, usePayments } from '@/features/billing/hooks/useBilling';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { billingService } from '@/features/billing/services/billingService';
import type { InvoiceStatus } from '@/features/billing/types/billing.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_TONE: Record<InvoiceStatus, StatusTone> = {
  draft: 'neutral',
  issued: 'info',
  partially_paid: 'warning',
  paid: 'success',
  void: 'danger',
  cancelled: 'danger',
};

function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

export function InvoiceDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('billing.manage');
  const { invoice, isLoading, error, refetch } = useInvoice(id);
  const { lines, refetch: refetchLines } = useInvoiceLines(id);
  const { payments, refetch: refetchPayments } = usePayments(id);
  const { client } = useClient(invoice?.clientId);
  const organization = useCurrentOrganization();

  const [description, setDescription] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [unitPrice, setUnitPrice] = useState('');
  const [isAddingLine, setIsAddingLine] = useState(false);

  const [issueDate, setIssueDate] = useState(new Date().toISOString().slice(0, 10));
  const [dueDate, setDueDate] = useState('');
  const [voidReason, setVoidReason] = useState('');

  const [paymentAmount, setPaymentAmount] = useState('');
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().slice(0, 10));
  const [paymentMethod, setPaymentMethod] = useState('');
  const [paymentReference, setPaymentReference] = useState('');

  const [actionError, setActionError] = useState<string | null>(null);
  const [isActing, setIsActing] = useState(false);

  if (isLoading) return <FullScreenSpinner label="Loading invoice…" />;
  if (error) return <FullScreenNotice title="Something went wrong" message={error} />;
  if (!invoice) {
    return (
      <FullScreenNotice
        title="Invoice not found"
        message="This invoice doesn't exist, or you don't have access to view it."
        action={
          <Link to="/invoices" className="focus-ring self-start rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Invoices
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
      await Promise.all([refetch(), refetchLines(), refetchPayments()]);
    } catch (err) {
      setActionError(getDbErrorMessage(err, failureMessage));
    } finally {
      setIsActing(false);
    }
  };

  const handleAddLine = async () => {
    if (!organization || !description.trim() || !unitPrice.trim()) return;
    setIsAddingLine(true);
    setActionError(null);
    try {
      await billingService.addInvoiceLine(organization.id, {
        invoiceId: invoice.id,
        description: description.trim(),
        quantity: Number(quantity),
        unitPrice: Number(unitPrice),
      });
      setDescription('');
      setUnitPrice('');
      await billingService.recomputeTotals(invoice.id);
      await Promise.all([refetch(), refetchLines()]);
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to add the line item.'));
    } finally {
      setIsAddingLine(false);
    }
  };

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button type="button" onClick={() => navigate('/invoices')} className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary">
        ← Back to Invoices
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{invoice.invoiceNumber}</h1>
            <p className="text-sm text-content-secondary">
              {client ? (
                <Link to={`/clients/${client.id}`} className="text-brand-600 hover:underline">
                  {client.name}
                </Link>
              ) : (
                'No client'
              )}
              <span className="ml-2 text-xs capitalize text-content-tertiary">{invoice.source.replace(/_/g, ' ')}</span>
            </p>
          </div>
          <StatusBadge label={invoice.status.replace(/_/g, ' ')} tone={STATUS_TONE[invoice.status]} />
        </div>

        <ErrorAlert message={actionError} />

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Subtotal</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(invoice.subtotal)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Tax ({invoice.taxRate}%)</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(invoice.taxAmount)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Total</dt>
            <dd className="mt-1 text-base font-semibold text-content-primary">{formatCurrency(invoice.totalAmount)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Outstanding</dt>
            <dd className="mt-1 text-base font-semibold text-content-primary">{formatCurrency(invoice.amountOutstanding)}</dd>
          </div>
        </dl>

        {invoice.voidReason && <p className="mt-4 text-sm text-danger-600">Voided: {invoice.voidReason}</p>}
      </div>

      {canManage && invoice.status === 'draft' && (
        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-content-primary">Line items</h2>
          {lines.length === 0 ? (
            <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">No line items yet.</p>
          ) : (
            <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
              {lines.map((line) => (
                <div key={line.id} className="flex items-center justify-between px-4 py-3 text-sm">
                  <span className="font-medium text-content-primary">{line.description}</span>
                  <span className="text-content-secondary">
                    {line.quantity} × {formatCurrency(line.unitPrice)} = {formatCurrency(line.lineTotal)}
                  </span>
                </div>
              ))}
            </div>
          )}
          <div className="flex flex-wrap items-end gap-2">
            <TextField label="Description" value={description} onChange={(event) => setDescription(event.target.value)} />
            <TextField label="Qty" type="number" min={0.01} step="0.01" value={quantity} onChange={(event) => setQuantity(event.target.value)} />
            <TextField label="Unit price (ZAR)" type="number" min={0} step="0.01" value={unitPrice} onChange={(event) => setUnitPrice(event.target.value)} />
            <Button variant="secondary" onClick={() => void handleAddLine()} isLoading={isAddingLine} disabled={!description.trim() || !unitPrice.trim()}>
              Add line
            </Button>
          </div>

          {invoice.totalAmount > 0 && (
            <div className="flex flex-wrap items-end gap-2 rounded-card border border-border bg-surface-raised p-4">
              <TextField label="Issue date" type="date" value={issueDate} onChange={(event) => setIssueDate(event.target.value)} />
              <TextField label="Due date" type="date" value={dueDate} onChange={(event) => setDueDate(event.target.value)} />
              <Button
                isLoading={isActing}
                disabled={!dueDate}
                onClick={() => void runAction(() => billingService.issueInvoice(invoice.id, issueDate, dueDate), 'Failed to issue this invoice.')}
              >
                Issue invoice
              </Button>
            </div>
          )}
        </section>
      )}

      {canManage && (invoice.status === 'issued' || invoice.status === 'partially_paid') && (
        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-content-primary">Record a payment</h2>
          <div className="flex flex-wrap items-end gap-2 rounded-card border border-border bg-surface-raised p-4">
            <TextField label="Amount (ZAR)" type="number" min={0.01} step="0.01" value={paymentAmount} onChange={(event) => setPaymentAmount(event.target.value)} />
            <TextField label="Date" type="date" value={paymentDate} onChange={(event) => setPaymentDate(event.target.value)} />
            <TextField label="Method" placeholder="EFT" value={paymentMethod} onChange={(event) => setPaymentMethod(event.target.value)} />
            <TextField label="Reference" value={paymentReference} onChange={(event) => setPaymentReference(event.target.value)} />
            <Button
              isLoading={isActing}
              disabled={!paymentAmount.trim()}
              onClick={() =>
                void runAction(async () => {
                  await billingService.recordPayment(invoice.id, Number(paymentAmount), paymentDate, paymentMethod.trim() || undefined, paymentReference.trim() || undefined);
                  setPaymentAmount('');
                  setPaymentReference('');
                }, 'Failed to record this payment.')
              }
            >
              Record payment
            </Button>
          </div>

          <div className="flex flex-col gap-2 rounded-card border border-border bg-surface-raised p-4">
            <h3 className="text-sm font-semibold text-content-primary">Void this invoice</h3>
            <div className="flex flex-wrap items-end gap-2">
              <TextField label="Reason" value={voidReason} onChange={(event) => setVoidReason(event.target.value)} />
              <Button
                variant="secondary"
                isLoading={isActing}
                disabled={!voidReason.trim()}
                onClick={() => void runAction(() => billingService.voidInvoice(invoice.id, voidReason.trim()), 'Failed to void this invoice.')}
              >
                Void invoice
              </Button>
            </div>
          </div>
        </section>
      )}

      {payments.length > 0 && (
        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-content-primary">Payment history</h2>
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {payments.map((payment) => (
              <div key={payment.id} className="flex items-center justify-between px-4 py-3 text-sm">
                <span className="text-content-primary">{new Date(payment.paymentDate).toLocaleDateString()}</span>
                <span className="text-content-secondary">{payment.method ?? '—'}</span>
                <span className="font-medium text-content-primary">{formatCurrency(payment.amount)}</span>
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
