import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useEmployee } from '@/features/employees/hooks/useEmployee';
import { useDepartments } from '@/features/employees/hooks/useDepartments';
import { usePositions } from '@/features/employees/hooks/usePositions';
import { employeeService } from '@/features/employees/services/employeeService';
import { EmployeeFormModal } from '@/features/employees/components/EmployeeFormModal';
import { TerminateEmployeeDialog } from '@/features/employees/components/TerminateEmployeeDialog';
import { ReactivateEmployeeDialog } from '@/features/employees/components/ReactivateEmployeeDialog';
import { ProvisionLoginModal } from '@/features/employees/components/ProvisionLoginModal';
import { useTeamsForEmployee } from '@/features/teams/hooks/useTeams';
import { useSiteAssignmentsForEmployee } from '@/features/siteAssignments/hooks/useSiteAssignments';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import type { Employee } from '@/features/employees/types/employee.types';

export function EmployeeProfilePage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('employee.manage');
  const organization = useCurrentOrganization();
  const { employee, isLoading, error, refetch } = useEmployee(id);
  const { departments } = useDepartments(organization?.id);
  const { positions } = usePositions(organization?.id);
  const { teams } = useTeamsForEmployee(id);
  const { assignments: currentAssignments } = useSiteAssignmentsForEmployee(organization?.id, id);
  const { sites } = useAllSites(organization?.id);

  const [manager, setManager] = useState<Employee | null>(null);
  const [isEditOpen, setIsEditOpen] = useState(false);
  const [isTerminateOpen, setIsTerminateOpen] = useState(false);
  const [isReactivateOpen, setIsReactivateOpen] = useState(false);
  const [isProvisionOpen, setIsProvisionOpen] = useState(false);

  useEffect(() => {
    if (!employee?.supervisorId) {
      setManager(null);
      return;
    }
    let cancelled = false;
    void employeeService.getEmployee(employee.supervisorId).then((result) => {
      if (!cancelled) setManager(result);
    });
    return () => {
      cancelled = true;
    };
  }, [employee?.supervisorId]);

  if (isLoading) {
    return <FullScreenSpinner label="Loading employee…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!employee) {
    return (
      <FullScreenNotice
        title="Employee not found"
        message="This employee doesn't exist, or you don't have access to view them."
        action={
          <Link to="/employees" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Employees
          </Link>
        }
      />
    );
  }

  const departmentName = departments.find((department) => department.id === employee.departmentId)?.name ?? '—';
  const positionTitle = positions.find((position) => position.id === employee.positionId)?.title ?? '—';
  const siteName = (siteId: string) => sites.find((s) => s.id === siteId)?.name ?? '—';

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/employees')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Employees
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-4">
            <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-brand-600 text-lg font-semibold text-white">
              {employee.firstName[0]}
              {employee.lastName[0]}
            </span>
            <div>
              <h1 className="text-xl font-bold text-content-primary">
                {employee.firstName} {employee.lastName}
              </h1>
              <p className="text-sm text-content-secondary">{employee.employeeNumber}</p>
            </div>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
            {employee.employmentStatus.replace(/_/g, ' ')}
          </span>
        </div>

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Department</dt>
            <dd className="mt-1 text-sm text-content-primary">{departmentName}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Position</dt>
            <dd className="mt-1 text-sm text-content-primary">{positionTitle}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Employment type</dt>
            <dd className="mt-1 text-sm capitalize text-content-primary">
              {employee.employmentType?.replace(/_/g, ' ') ?? '—'}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Start date</dt>
            <dd className="mt-1 text-sm text-content-primary">{employee.employmentStartDate}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">End date</dt>
            <dd className="mt-1 text-sm text-content-primary">{employee.employmentEndDate ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Email</dt>
            <dd className="mt-1 text-sm text-content-primary">{employee.email ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Phone</dt>
            <dd className="mt-1 text-sm text-content-primary">{employee.phone ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Reports to</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {manager ? `${manager.firstName} ${manager.lastName}` : '—'}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Application login</dt>
            <dd className="mt-1 text-sm text-content-primary">{employee.profileId ? 'Linked' : 'None'}</dd>
          </div>
        </dl>

        {canManage && (
          <div className="mt-6 flex flex-wrap gap-3 border-t border-border pt-5">
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" onClick={() => setIsEditOpen(true)}>
                Edit details
              </Button>
            </div>
            {!employee.profileId && (
              <div className="w-full sm:w-auto sm:min-w-[8rem]">
                <Button type="button" variant="secondary" onClick={() => setIsProvisionOpen(true)}>
                  Provision login
                </Button>
              </div>
            )}
            {employee.employmentStatus === 'terminated' ? (
              <div className="w-full sm:w-auto sm:min-w-[8rem]">
                <Button type="button" variant="secondary" onClick={() => setIsReactivateOpen(true)}>
                  Reactivate
                </Button>
              </div>
            ) : (
              <div className="w-full sm:w-auto sm:min-w-[8rem]">
                <Button type="button" variant="secondary" onClick={() => setIsTerminateOpen(true)}>
                  Terminate
                </Button>
              </div>
            )}
          </div>
        )}
      </div>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Teams</h2>
        {teams.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            Not a member of any team yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {teams.map((team) => (
              <Link
                key={team.id}
                to={`/teams/${team.id}`}
                className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
              >
                <span className="font-medium text-content-primary">{team.name}</span>
              </Link>
            ))}
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Current Sites</h2>
        {currentAssignments.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No current site assignments.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {currentAssignments.map((assignment) => (
              <Link
                key={assignment.id}
                to={`/sites/${assignment.siteId}`}
                className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
              >
                <span className="font-medium text-content-primary">{siteName(assignment.siteId)}</span>
                {assignment.roleOnSite && <span className="text-xs text-content-tertiary">{assignment.roleOnSite}</span>}
              </Link>
            ))}
          </div>
        )}
      </section>

      {organization && (
        <EmployeeFormModal
          isOpen={isEditOpen}
          onClose={() => setIsEditOpen(false)}
          tenantId={organization.id}
          employee={employee}
          departments={departments}
          positions={positions}
          onSaved={() => void refetch()}
        />
      )}
      <TerminateEmployeeDialog
        isOpen={isTerminateOpen}
        onClose={() => setIsTerminateOpen(false)}
        employee={employee}
        onTerminated={() => void refetch()}
      />
      <ReactivateEmployeeDialog
        isOpen={isReactivateOpen}
        onClose={() => setIsReactivateOpen(false)}
        employee={employee}
        onReactivated={() => void refetch()}
      />
      <ProvisionLoginModal
        isOpen={isProvisionOpen}
        onClose={() => setIsProvisionOpen(false)}
        employee={employee}
        onProvisioned={() => void refetch()}
      />
    </div>
  );
}
