import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import type { Quote, QuoteStatus } from '@/features/quotes/types/quote.types';
import type { Client } from '@/features/orgStructure/types/orgStructure.types';

export interface QuotesTableProps {
  quotes: Quote[];
  clients: Client[];
}

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

function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

export function QuotesTable({ quotes, clients }: QuotesTableProps) {
  if (quotes.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No quotes match your filters.
      </div>
    );
  }

  const clientName = (clientId: string) => clients.find((c) => c.id === clientId)?.name ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Quote #
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Client
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Total
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {quotes.map((quote) => (
            <tr key={quote.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                <Link to={`/quotes/${quote.id}`} className="focus-ring rounded hover:text-brand-600">
                  {quote.quoteNumber}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">{clientName(quote.clientId)}</td>
              <td className="px-4 py-3 text-content-secondary">{formatCurrency(quote.totalAmount)}</td>
              <td className="px-4 py-3">
                <StatusBadge label={quote.status} tone={STATUS_TONE[quote.status]} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
