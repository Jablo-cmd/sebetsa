import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useShiftDefinitions } from '@/features/scheduling/hooks/useShiftDefinitions';
import { shiftDefinitionService } from '@/features/scheduling/services/shiftDefinitionService';
import { ShiftDefinitionsTable } from '@/features/scheduling/components/ShiftDefinitionsTable';
import { ShiftDefinitionFormModal } from '@/features/scheduling/components/ShiftDefinitionFormModal';
import type { ShiftDefinition } from '@/features/scheduling/types/scheduling.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function ShiftDefinitionsPage() {
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('scheduling.manage');
  const organization = useCurrentOrganization();
  const { shiftDefinitions, isLoading, error, refetch } = useShiftDefinitions(organization?.id);

  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingDefinition, setEditingDefinition] = useState<ShiftDefinition | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const openCreate = () => {
    setEditingDefinition(null);
    setIsFormOpen(true);
  };

  const openEdit = (definition: ShiftDefinition) => {
    setEditingDefinition(definition);
    setIsFormOpen(true);
  };

  const handleToggleActive = async (definition: ShiftDefinition) => {
    setActionError(null);
    try {
      if (definition.status === 'active') {
        await shiftDefinitionService.archiveShiftDefinition(definition.id);
      } else {
        await shiftDefinitionService.restoreShiftDefinition(definition.id);
      }
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to update shift definition.'));
    }
  };

  return (
    <PageContainer>
      <button
        type="button"
        onClick={() => navigate('/schedule')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Schedule
      </button>

      <PageHeader
        title="Shift Definitions"
        description="Reusable shift templates (e.g. Day Shift, 08:00-17:00) that can be picked when scheduling — a shift never requires one."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[10rem]">
              <Button type="button" onClick={openCreate}>
                Add shift definition
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={error ?? actionError} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="shift definitions" />
      ) : isLoading ? (
        <LoadingBlock label="Loading shift definitions…" />
      ) : (
        <ShiftDefinitionsTable
          shiftDefinitions={shiftDefinitions}
          canManage={canManage}
          onEdit={openEdit}
          onToggleActive={(definition) => void handleToggleActive(definition)}
        />
      )}

      {organization && (
        <ShiftDefinitionFormModal
          isOpen={isFormOpen}
          onClose={() => setIsFormOpen(false)}
          tenantId={organization.id}
          shiftDefinition={editingDefinition}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
