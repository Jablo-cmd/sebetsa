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
import { useDepartments } from '@/features/employees/hooks/useDepartments';
import { departmentService } from '@/features/employees/services/departmentService';
import { DepartmentsTable } from '@/features/employees/components/DepartmentsTable';
import { DepartmentFormModal } from '@/features/employees/components/DepartmentFormModal';
import type { Department } from '@/features/employees/types/employee.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function DepartmentsPage() {
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('employee.manage');
  const organization = useCurrentOrganization();
  const { departments, isLoading, error, refetch } = useDepartments(organization?.id);

  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingDepartment, setEditingDepartment] = useState<Department | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const openCreate = () => {
    setEditingDepartment(null);
    setIsFormOpen(true);
  };

  const openEdit = (department: Department) => {
    setEditingDepartment(department);
    setIsFormOpen(true);
  };

  const handleDelete = async (department: Department) => {
    setActionError(null);
    try {
      await departmentService.deleteDepartment(department.id);
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to delete department.'));
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
        title="Departments"
        description="Manage the department catalogue for your organization."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={openCreate}>
                Add department
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={error ?? actionError} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="departments" />
      ) : isLoading ? (
        <LoadingBlock label="Loading departments…" />
      ) : (
        <DepartmentsTable departments={departments} canManage={canManage} onEdit={openEdit} onDelete={(department) => void handleDelete(department)} />
      )}

      {organization && (
        <DepartmentFormModal
          isOpen={isFormOpen}
          onClose={() => setIsFormOpen(false)}
          tenantId={organization.id}
          department={editingDepartment}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
