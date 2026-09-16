import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { DataTable, type DataTableColumn } from '@/components/ui/DataTable';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useInvoicesList } from '@/features/billing/hooks/useBilling';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { CreateInvoiceModal } from '@/features/billing/components/CreateInvoiceModal';
import type { Invoice, InvoiceStatus } from '@/features/billing/types/billing.types';

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

/** Server-authoritative invoicing — subtotal/tax/total are always derived from real line items, never a client-submitted figure. */
export function InvoicesPage() {
  const { can } = usePermissions();
  const canManage = can('billing.manage');
  const organization = useCurrentOrganization();
  const { invoices, isLoading, error, refetch } = useInvoicesList(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const navigate = useNavigate();

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  const clientName = (id: string) => clients.find((client) => client.id === id)?.name ?? '—';

  const columns: DataTableColumn<Invoice>[] = [
    { key: 'number', header: 'Invoice #', render: (row) => <span className="font-medium text-content-primary">{row.invoiceNumber}</span> },
    { key: 'client', header: 'Client', render: (row) => clientName(row.clientId) },
    { key: 'source', header: 'Source', render: (row) => <span className="capitalize">{row.source.replace(/_/g, ' ')}</span> },
    { key: 'total', header: 'Total', align: 'right', render: (row) => formatCurrency(row.totalAmount) },
    { key: 'outstanding', header: 'Outstanding', align: 'right', render: (row) => formatCurrency(row.amountOutstanding) },
    { key: 'status', header: 'Status', render: (row) => <StatusBadge label={row.status.replace(/_/g, ' ')} tone={STATUS_TONE[row.status]} /> },
  ];

  return (
    <PageContainer>
      <PageHeader
        title="Invoices"
        description="Server-computed billing — totals are always derived from real line items and cannot be edited directly."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)} disabled={clients.length === 0}>
                Create draft invoice
              </Button>
            </div>
          )
        }
      />
      <ErrorAlert message={error} />
      {!organization ? (
        <NoActiveOrganizationNotice resource="invoices" />
      ) : (
        <DataTable
          columns={columns}
          rows={invoices}
          getRowKey={(row) => row.id}
          isLoading={isLoading}
          loadingLabel="Loading invoices…"
          emptyMessage="No invoices yet."
          onRowClick={(row) => navigate(`/invoices/${row.id}`)}
        />
      )}
      {organization && (
        <CreateInvoiceModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          clients={clients}
          onCreated={(invoiceId) => {
            setIsCreateOpen(false);
            void refetch();
            navigate(`/invoices/${invoiceId}`);
          }}
        />
      )}
    </PageContainer>
  );
}
