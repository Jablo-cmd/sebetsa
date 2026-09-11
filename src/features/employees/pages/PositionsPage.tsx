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
import { usePositions } from '@/features/employees/hooks/usePositions';
import { useDepartments } from '@/features/employees/hooks/useDepartments';
import { positionService } from '@/features/employees/services/positionService';
import { PositionsTable } from '@/features/employees/components/PositionsTable';
import { PositionFormModal } from '@/features/employees/components/PositionFormModal';
import type { Position } from '@/features/employees/types/employee.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function PositionsPage() {
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('position.manage');
  const organization = useCurrentOrganization();
  const { positions, isLoading, error, refetch } = usePositions(organization?.id);
  const { departments } = useDepartments(organization?.id);

  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingPosition, setEditingPosition] = useState<Position | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const openCreate = () => {
    setEditingPosition(null);
    setIsFormOpen(true);
  };

  const openEdit = (position: Position) => {
    setEditingPosition(position);
    setIsFormOpen(true);
  };

  const handleToggleActive = async (position: Position) => {
    setActionError(null);
    try {
      if (position.status === 'active') {
        await positionService.archivePosition(position.id);
      } else {
        await positionService.restorePosition(position.id);
      }
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to update position.'));
    }
  };

  return (
    <PageContainer>
      <button
        type="button"
        onClick={() => navigate('/employees')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Employees
      </button>

      <PageHeader
        title="Positions"
        description="The job titles workforce members are assigned to, e.g. Cleaner, Site Supervisor."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={openCreate}>
                Add position
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={error ?? actionError} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="positions" />
      ) : isLoading ? (
        <LoadingBlock label="Loading positions…" />
      ) : (
        <PositionsTable
          positions={positions}
          departments={departments}
          canManage={canManage}
          onEdit={openEdit}
          onToggleActive={(position) => void handleToggleActive(position)}
        />
      )}

      {organization && (
        <PositionFormModal
          isOpen={isFormOpen}
          onClose={() => setIsFormOpen(false)}
          tenantId={organization.id}
          position={editingPosition}
          departments={departments}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
