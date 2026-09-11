import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useEmployeesList } from '@/features/employees/hooks/useEmployeesList';
import { useDepartments } from '@/features/employees/hooks/useDepartments';
import { EmployeesFiltersBar } from '@/features/employees/components/EmployeesFiltersBar';
import { EmployeesTable } from '@/features/employees/components/EmployeesTable';
import { EmployeesPagination } from '@/features/employees/components/EmployeesPagination';
import { EmployeeFormModal } from '@/features/employees/components/EmployeeFormModal';
import { TerminateEmployeeDialog } from '@/features/employees/components/TerminateEmployeeDialog';
import { ReactivateEmployeeDialog } from '@/features/employees/components/ReactivateEmployeeDialog';
import type { Employee } from '@/features/employees/types/employee.types';

export function EmployeesPage() {
  const { can } = usePermissions();
  const canManage = can('employee.manage');
  const organization = useCurrentOrganization();
  const {
    employees,
    totalCount,
    page,
    pageSize,
    isLoading,
    error,
    filters,
    setFilters,
    setPage,
    refetch,
  } = useEmployeesList(organization?.id);
  const { departments } = useDepartments(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [editingEmployee, setEditingEmployee] = useState<Employee | null>(null);
  const [terminatingEmployee, setTerminatingEmployee] = useState<Employee | null>(null);
  const [reactivatingEmployee, setReactivatingEmployee] = useState<Employee | null>(null);

  return (
    <PageContainer>
      <PageHeader
        title="Employees"
        description="Manage the workforce directory for your organization."
        action={
          <div className="flex flex-wrap gap-3">
            <Link
              to="/employees/departments"
              className="focus-ring flex h-11 items-center rounded-lg px-3.5 text-sm font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
            >
              Manage departments
            </Link>
            {canManage && organization && (
              <div className="w-full sm:w-auto sm:min-w-[9rem]">
                <Button type="button" onClick={() => setIsCreateOpen(true)}>
                  Add employee
                </Button>
              </div>
            )}
          </div>
        }
      />

      {organization && (
        <EmployeesFiltersBar filters={filters} departments={departments} onChange={setFilters} />
      )}

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="employees" />
      ) : isLoading ? (
        <LoadingBlock label="Loading employees…" />
      ) : (
        <>
          <EmployeesTable
            employees={employees}
            departments={departments}
            canManage={canManage}
            onEdit={setEditingEmployee}
            onTerminate={setTerminatingEmployee}
            onReactivate={setReactivatingEmployee}
          />
          <EmployeesPagination
            page={page}
            pageSize={pageSize}
            totalCount={totalCount}
            onPageChange={setPage}
          />
        </>
      )}

      {organization && (
        <EmployeeFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          departments={departments}
          onSaved={() => void refetch()}
        />
      )}

      {editingEmployee && organization && (
        <EmployeeFormModal
          isOpen={Boolean(editingEmployee)}
          onClose={() => setEditingEmployee(null)}
          tenantId={organization.id}
          employee={editingEmployee}
          departments={departments}
          onSaved={() => void refetch()}
        />
      )}
      {terminatingEmployee && (
        <TerminateEmployeeDialog
          isOpen={Boolean(terminatingEmployee)}
          onClose={() => setTerminatingEmployee(null)}
          employee={terminatingEmployee}
          onTerminated={() => void refetch()}
        />
      )}
      {reactivatingEmployee && (
        <ReactivateEmployeeDialog
          isOpen={Boolean(reactivatingEmployee)}
          onClose={() => setReactivatingEmployee(null)}
          employee={reactivatingEmployee}
          onReactivated={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
