import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Pagination } from '@/components/ui/Pagination';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useContractsList } from '@/features/orgStructure/hooks/useContracts';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { ContractsFiltersBar } from '@/features/orgStructure/components/ContractsFiltersBar';
import { ContractsTable } from '@/features/orgStructure/components/ContractsTable';
import { ContractFormModal } from '@/features/orgStructure/components/ContractFormModal';

export function ContractsPage() {
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { contracts, totalCount, page, pageSize, isLoading, error, filters, setFilters, setPage, refetch } =
    useContractsList(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const { sites } = useAllSites(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  return (
    <PageContainer>
      <PageHeader
        title="Contracts"
        description="Service agreements between your organization and a client."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)} disabled={clients.length === 0}>
                Add contract
              </Button>
            </div>
          )
        }
      />

      {organization && clients.length === 0 && (
        <p className="rounded-card border border-dashed border-border-strong bg-surface-raised px-4 py-6 text-center text-sm text-content-tertiary">
          Add a client before creating contracts — every contract belongs to one.
        </p>
      )}

      {organization && <ContractsFiltersBar filters={filters} clients={clients} onChange={setFilters} />}

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="contracts" />
      ) : isLoading ? (
        <LoadingBlock label="Loading contracts…" />
      ) : (
        <>
          <ContractsTable contracts={contracts} clients={clients} />
          <Pagination page={page} pageSize={pageSize} totalCount={totalCount} onPageChange={setPage} resource="contracts" />
        </>
      )}

      {organization && (
        <ContractFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          clients={clients}
          sites={sites}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
