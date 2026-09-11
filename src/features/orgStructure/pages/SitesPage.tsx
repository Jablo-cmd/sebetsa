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
import { useSitesList } from '@/features/orgStructure/hooks/useSites';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { useRegions } from '@/features/orgStructure/hooks/useRegions';
import { SitesFiltersBar } from '@/features/orgStructure/components/SitesFiltersBar';
import { SitesTable } from '@/features/orgStructure/components/SitesTable';
import { SiteFormModal } from '@/features/orgStructure/components/SiteFormModal';

export function SitesPage() {
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { sites, totalCount, page, pageSize, isLoading, error, filters, setFilters, setPage, refetch } =
    useSitesList(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const { regions } = useRegions(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  return (
    <PageContainer>
      <PageHeader
        title="Sites"
        description="Physical locations where services are delivered for a client."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)} disabled={clients.length === 0}>
                Add site
              </Button>
            </div>
          )
        }
      />

      {organization && clients.length === 0 && (
        <p className="rounded-card border border-dashed border-border-strong bg-surface-raised px-4 py-6 text-center text-sm text-content-tertiary">
          Add a client before creating sites — every site belongs to one.
        </p>
      )}

      {organization && <SitesFiltersBar filters={filters} clients={clients} regions={regions} onChange={setFilters} />}

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="sites" />
      ) : isLoading ? (
        <LoadingBlock label="Loading sites…" />
      ) : (
        <>
          <SitesTable sites={sites} clients={clients} regions={regions} />
          <Pagination page={page} pageSize={pageSize} totalCount={totalCount} onPageChange={setPage} resource="sites" />
        </>
      )}

      {organization && (
        <SiteFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          clients={clients}
          regions={regions}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
