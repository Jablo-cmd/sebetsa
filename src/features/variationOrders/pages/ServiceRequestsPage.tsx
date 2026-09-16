import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { DataTable, type DataTableColumn } from '@/components/ui/DataTable';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { Button } from '@/components/ui/Button';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useServiceRequests } from '@/features/variationOrders/hooks/useVariationOrders';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { AssessRequestModal } from '@/features/variationOrders/components/AssessRequestModal';
import type { ServiceRequest, ServiceRequestStatus } from '@/features/variationOrders/types/variationOrder.types';

const STATUS_TONE: Record<ServiceRequestStatus, StatusTone> = {
  requested: 'info',
  assessed: 'warning',
  converted: 'success',
  rejected: 'danger',
  cancelled: 'neutral',
};

/** The front door for client-submitted or internally-raised work outside a contract's existing scope. Assessing a request creates a real variation_orders row. */
export function ServiceRequestsPage() {
  const { can } = usePermissions();
  const canManage = can('variation.manage');
  const organization = useCurrentOrganization();
  const { serviceRequests, isLoading, error, refetch } = useServiceRequests(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const navigate = useNavigate();

  const [assessing, setAssessing] = useState<ServiceRequest | null>(null);

  const clientName = (id: string) => clients.find((client) => client.id === id)?.name ?? '—';

  const columns: DataTableColumn<ServiceRequest>[] = [
    { key: 'client', header: 'Client', render: (row) => clientName(row.clientId) },
    { key: 'type', header: 'Type', render: (row) => <span className="capitalize">{row.requestType.replace(/_/g, ' ')}</span> },
    { key: 'description', header: 'Description', render: (row) => <span className="line-clamp-1">{row.description}</span> },
    { key: 'origin', header: 'Origin', render: (row) => <span className="capitalize">{row.origin}</span> },
    { key: 'status', header: 'Status', render: (row) => <StatusBadge label={row.status} tone={STATUS_TONE[row.status]} /> },
    {
      key: 'actions',
      header: '',
      align: 'right',
      render: (row) =>
        canManage && row.status === 'requested' ? (
          <Button variant="secondary" className="h-8 px-3 text-xs" onClick={() => setAssessing(row)}>
            Assess
          </Button>
        ) : null,
    },
  ];

  return (
    <PageContainer>
      <PageHeader title="Service Requests" description="Additional work requested by clients or raised internally — assess one to turn it into a billable variation." />
      <ErrorAlert message={error} />
      {!organization ? (
        <NoActiveOrganizationNotice resource="service requests" />
      ) : (
        <DataTable
          columns={columns}
          rows={serviceRequests}
          getRowKey={(row) => row.id}
          isLoading={isLoading}
          loadingLabel="Loading service requests…"
          emptyMessage="No service requests yet."
        />
      )}
      <AssessRequestModal
        isOpen={assessing !== null}
        onClose={() => setAssessing(null)}
        request={assessing}
        onAssessed={(variationId) => {
          setAssessing(null);
          void refetch();
          navigate(`/variation-orders/${variationId}`);
        }}
      />
    </PageContainer>
  );
}
