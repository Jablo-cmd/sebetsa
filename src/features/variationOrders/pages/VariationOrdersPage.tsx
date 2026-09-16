import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { DataTable, type DataTableColumn } from '@/components/ui/DataTable';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useVariationOrdersList } from '@/features/variationOrders/hooks/useVariationOrders';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import type { VariationOrder, VariationOrderStatus } from '@/features/variationOrders/types/variationOrder.types';

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

/** Billable work outside a contract's existing scope — VARIATION -> QUOTE -> CLIENT APPROVAL -> WORK -> COMPLETION -> INVOICE. */
export function VariationOrdersPage() {
  const organization = useCurrentOrganization();
  const { variationOrders, isLoading, error } = useVariationOrdersList(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const navigate = useNavigate();

  const clientName = (id: string) => clients.find((client) => client.id === id)?.name ?? '—';

  const columns: DataTableColumn<VariationOrder>[] = [
    { key: 'title', header: 'Title', render: (row) => <span className="font-medium text-content-primary">{row.title}</span> },
    { key: 'client', header: 'Client', render: (row) => clientName(row.clientId) },
    { key: 'status', header: 'Status', render: (row) => <StatusBadge label={row.status.replace(/_/g, ' ')} tone={STATUS_TONE[row.status]} /> },
    { key: 'created', header: 'Created', render: (row) => new Date(row.createdAt).toLocaleDateString() },
  ];

  return (
    <PageContainer>
      <PageHeader title="Variation Orders" description="Billable additional work attached to an existing contract — from client approval through completion and invoicing." />
      <ErrorAlert message={error} />
      {!organization ? (
        <NoActiveOrganizationNotice resource="variation orders" />
      ) : (
        <DataTable
          columns={columns}
          rows={variationOrders}
          getRowKey={(row) => row.id}
          isLoading={isLoading}
          loadingLabel="Loading variation orders…"
          emptyMessage="No variation orders yet — assess a service request to create one."
          onRowClick={(row) => navigate(`/variation-orders/${row.id}`)}
        />
      )}
    </PageContainer>
  );
}
