import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useClientsList } from '@/features/orgStructure/hooks/useClients';
import { useRegions } from '@/features/orgStructure/hooks/useRegions';
import { ClientsFiltersBar } from '@/features/orgStructure/components/ClientsFiltersBar';
import { ClientsTable } from '@/features/orgStructure/components/ClientsTable';
import { Pagination } from '@/components/ui/Pagination';
import { ClientFormModal } from '@/features/orgStructure/components/ClientFormModal';

export function ClientsPage() {
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { clients, totalCount, page, pageSize, isLoading, error, filters, setFilters, setPage, refetch } =
    useClientsList(organization?.id);
  const { regions } = useRegions(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  return (
    <PageContainer>
      <PageHeader
        title="Clients"
        description="Customer organizations Sebetsa provides services to."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)}>
                Add client
              </Button>
            </div>
          )
        }
      />

      {organization && <ClientsFiltersBar filters={filters} regions={regions} onChange={setFilters} />}

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="clients" />
      ) : isLoading ? (
        <LoadingBlock label="Loading clients…" />
      ) : (
        <>
          <ClientsTable clients={clients} regions={regions} />
          <Pagination page={page} pageSize={pageSize} totalCount={totalCount} onPageChange={setPage} resource="clients" />
        </>
      )}

      {organization && (
        <ClientFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          regions={regions}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
