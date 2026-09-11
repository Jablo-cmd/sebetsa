import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useRegions } from '@/features/orgStructure/hooks/useRegions';
import { regionService } from '@/features/orgStructure/services/regionService';
import { RegionsTable } from '@/features/orgStructure/components/RegionsTable';
import { RegionFormModal } from '@/features/orgStructure/components/RegionFormModal';
import type { Region } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function RegionsPage() {
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { regions, isLoading, error, refetch } = useRegions(organization?.id);

  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingRegion, setEditingRegion] = useState<Region | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const openCreate = () => {
    setEditingRegion(null);
    setIsFormOpen(true);
  };

  const openEdit = (region: Region) => {
    setEditingRegion(region);
    setIsFormOpen(true);
  };

  const handleToggleActive = async (region: Region) => {
    setActionError(null);
    try {
      if (region.status === 'active') {
        await regionService.archiveRegion(region.id);
      } else {
        await regionService.restoreRegion(region.id);
      }
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to update region.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Regions"
        description="Geographic or operational groupings used to organize clients and sites."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={openCreate}>
                Add region
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={error ?? actionError} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="regions" />
      ) : isLoading ? (
        <LoadingBlock label="Loading regions…" />
      ) : (
        <RegionsTable
          regions={regions}
          canManage={canManage}
          onEdit={openEdit}
          onToggleActive={(region) => void handleToggleActive(region)}
        />
      )}

      {organization && (
        <RegionFormModal
          isOpen={isFormOpen}
          onClose={() => setIsFormOpen(false)}
          tenantId={organization.id}
          region={editingRegion}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
