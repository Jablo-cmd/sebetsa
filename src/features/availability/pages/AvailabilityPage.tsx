import { useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { TextField } from '@/components/ui/TextField';
import { usePermissions } from '@/hooks/usePermissions';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { useAvailability } from '@/features/availability/hooks/useAvailability';
import { availabilityService } from '@/features/availability/services/availabilityService';
import { AvailabilityWeekEditor } from '@/features/availability/components/AvailabilityWeekEditor';
import { AvailabilityExceptionsPanel } from '@/features/availability/components/AvailabilityExceptionsPanel';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function AvailabilityPage() {
  const { can } = usePermissions();
  const canManageOthers = can('availability.manage');
  const organization = useCurrentOrganization();
  const { data: myEmployee, isLoading: myEmployeeLoading } = useMyEmployee();

  const [targetEmployee, setTargetEmployee] = useState<EmployeeCandidate | null>(null);
  const [employeeSearch, setEmployeeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);

  useEffect(() => {
    if (myEmployee && !targetEmployee) {
      setTargetEmployee({ id: myEmployee.id, firstName: myEmployee.firstName, lastName: myEmployee.lastName });
    }
  }, [myEmployee, targetEmployee]);

  useEffect(() => {
    if (!canManageOthers || !organization) return;
    let cancelled = false;
    void employeeService.searchEmployeeCandidates(organization.id, employeeSearch).then((results) => {
      if (!cancelled) setCandidates(results);
    });
    return () => {
      cancelled = true;
    };
  }, [canManageOthers, organization, employeeSearch]);

  const { windows, exceptions, isLoading, error, refetch } = useAvailability(targetEmployee?.id);
  const [actionError, setActionError] = useState<string | null>(null);

  const isOwnRecord = targetEmployee?.id === myEmployee?.id;
  const canManageTarget = isOwnRecord || canManageOthers;

  const handleAddWindow = async (values: { dayOfWeek: number; startTime: string; endTime: string }) => {
    if (!organization || !targetEmployee) return;
    setActionError(null);
    try {
      await availabilityService.createWindow(organization.id, {
        employeeId: targetEmployee.id,
        dayOfWeek: values.dayOfWeek as 0 | 1 | 2 | 3 | 4 | 5 | 6,
        startTime: values.startTime,
        endTime: values.endTime,
      });
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to add availability window.'));
    }
  };

  const handleDeleteWindow = async (id: string) => {
    setActionError(null);
    try {
      await availabilityService.deleteWindow(id);
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to remove availability window.'));
    }
  };

  const handleAddException = async (values: {
    exceptionDate: string;
    isAvailable: boolean;
    startTime?: string;
    endTime?: string;
    reason?: string;
  }) => {
    if (!organization || !targetEmployee) return;
    setActionError(null);
    try {
      await availabilityService.createException(organization.id, {
        employeeId: targetEmployee.id,
        exceptionDate: values.exceptionDate,
        isAvailable: values.isAvailable,
        startTime: values.startTime?.trim() || null,
        endTime: values.endTime?.trim() || null,
        reason: values.reason?.trim() || null,
      });
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to add exception.'));
    }
  };

  const handleDeleteException = async (id: string) => {
    setActionError(null);
    try {
      await availabilityService.deleteException(id);
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to remove exception.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Availability"
        description="Recurring weekly availability, plus date-specific exceptions — is an employee generally free to be scheduled."
      />

      <ErrorAlert message={error ?? actionError} />

      {canManageOthers && (
        <div className="rounded-card border border-border bg-surface-raised p-4">
          <TextField
            label="Manage availability for"
            hint={targetEmployee ? `Currently viewing: ${targetEmployee.firstName} ${targetEmployee.lastName}` : 'Search by name…'}
            placeholder="Search by name…"
            value={employeeSearch}
            onChange={(event) => setEmployeeSearch(event.target.value)}
          />
          {employeeSearch && (
            <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
              {candidates.map((candidate) => (
                <button
                  key={candidate.id}
                  type="button"
                  onClick={() => {
                    setTargetEmployee(candidate);
                    setEmployeeSearch('');
                  }}
                  className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3 py-2 text-left text-sm hover:bg-surface-sunken"
                >
                  {candidate.firstName} {candidate.lastName}
                </button>
              ))}
            </div>
          )}
          {myEmployee && targetEmployee?.id !== myEmployee.id && (
            <button
              type="button"
              onClick={() => setTargetEmployee({ id: myEmployee.id, firstName: myEmployee.firstName, lastName: myEmployee.lastName })}
              className="focus-ring mt-2 rounded-md px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50 dark:hover:bg-brand-500/10"
            >
              ← Back to my own availability
            </button>
          )}
        </div>
      )}

      {myEmployeeLoading || (targetEmployee && isLoading) ? (
        <LoadingBlock label="Loading availability…" />
      ) : !targetEmployee ? (
        <p className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
          {canManageOthers
            ? 'Search for an employee above to view or manage their availability.'
            : 'No employee record is linked to your account, so there is no availability to manage.'}
        </p>
      ) : (
        <>
          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-content-primary">Weekly availability</h2>
            <AvailabilityWeekEditor
              windows={windows}
              canManage={canManageTarget}
              onAdd={handleAddWindow}
              onDelete={handleDeleteWindow}
            />
          </section>

          <section className="flex flex-col gap-2">
            <h2 className="text-sm font-semibold text-content-primary">Exceptions</h2>
            <AvailabilityExceptionsPanel
              exceptions={exceptions}
              canManage={canManageTarget}
              onAdd={handleAddException}
              onDelete={handleDeleteException}
            />
          </section>
        </>
      )}
    </PageContainer>
  );
}
