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
import { useInspectionsList, useInspectionTemplates } from '@/features/cleaningQa/hooks/useCleaningQa';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { ScheduleInspectionModal } from '@/features/cleaningQa/components/ScheduleInspectionModal';
import type { Inspection, InspectionStatus } from '@/features/cleaningQa/types/cleaningQa.types';

const STATUS_TONE: Record<InspectionStatus, StatusTone> = {
  scheduled: 'neutral',
  in_progress: 'info',
  completed: 'warning',
  closed: 'success',
};

/** Cleaning quality inspections — deterministic weighted scoring, distinct from the guard-tour/patrol-checkpoint system. */
export function InspectionsPage() {
  const { can } = usePermissions();
  const canManage = can('inspection.manage');
  const organization = useCurrentOrganization();
  const { inspections, isLoading, error, refetch } = useInspectionsList(organization?.id);
  const { templates } = useInspectionTemplates(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const { sites } = useAllSites(organization?.id);
  const navigate = useNavigate();

  const [isScheduleOpen, setIsScheduleOpen] = useState(false);

  const clientName = (id: string) => clients.find((client) => client.id === id)?.name ?? '—';
  const siteName = (id: string) => sites.find((site) => site.id === id)?.name ?? '—';

  const columns: DataTableColumn<Inspection>[] = [
    { key: 'site', header: 'Site', render: (row) => siteName(row.siteId) },
    { key: 'client', header: 'Client', render: (row) => clientName(row.clientId) },
    { key: 'status', header: 'Status', render: (row) => <StatusBadge label={row.status.replace(/_/g, ' ')} tone={STATUS_TONE[row.status]} /> },
    {
      key: 'score',
      header: 'Score',
      align: 'right',
      render: (row) => (row.overallScore !== null ? `${row.overallScore}% ${row.passed ? '✓' : '✗'}` : '—'),
    },
    { key: 'scheduled', header: 'Scheduled', render: (row) => (row.scheduledAt ? new Date(row.scheduledAt).toLocaleString() : '—') },
  ];

  return (
    <PageContainer>
      <PageHeader
        title="Cleaning QA"
        description="Cleaning quality inspections — deterministic weighted scoring against real submitted results, never an AI judgement."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsScheduleOpen(true)} disabled={templates.length === 0}>
                Schedule inspection
              </Button>
            </div>
          )
        }
      />
      {organization && templates.length === 0 && (
        <p className="rounded-card border border-dashed border-border-strong bg-surface-raised px-4 py-6 text-center text-sm text-content-tertiary">
          Create an inspection template before scheduling an inspection.
        </p>
      )}
      <ErrorAlert message={error} />
      {!organization ? (
        <NoActiveOrganizationNotice resource="inspections" />
      ) : (
        <DataTable
          columns={columns}
          rows={inspections}
          getRowKey={(row) => row.id}
          isLoading={isLoading}
          loadingLabel="Loading inspections…"
          emptyMessage="No inspections yet."
          onRowClick={(row) => navigate(`/inspections/${row.id}`)}
        />
      )}
      {organization && (
        <ScheduleInspectionModal
          isOpen={isScheduleOpen}
          onClose={() => setIsScheduleOpen(false)}
          tenantId={organization.id}
          clients={clients}
          sites={sites}
          templates={templates}
          onScheduled={(inspectionId) => {
            setIsScheduleOpen(false);
            void refetch();
            navigate(`/inspections/${inspectionId}`);
          }}
        />
      )}
    </PageContainer>
  );
}
