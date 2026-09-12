import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { Button } from '@/components/ui/Button';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useLeaveRequests } from '@/features/leave/hooks/useLeaveRequests';
import { useLeaveTypes } from '@/features/leave/hooks/useLeaveTypes';
import { useLeaveBalances } from '@/features/leave/hooks/useLeaveBalances';
import { LeaveRequestFormModal } from '@/features/leave/components/LeaveRequestFormModal';
import { LeaveRequestsTable } from '@/features/leave/components/LeaveRequestsTable';
import { leaveService } from '@/features/leave/services/leaveService';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function MyLeavePage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();
  const { leaveTypes } = useLeaveTypes(employee?.tenantId);
  const {
    leaveRequests,
    isLoading: requestsLoading,
    error: requestsError,
    refetch: refetchRequests,
  } = useLeaveRequests(employee?.tenantId, { employeeId: employee?.id });
  const { balances, isLoading: balancesLoading } = useLeaveBalances(employee?.tenantId, {
    employeeId: employee?.id,
    periodYear: new Date().getFullYear(),
  });

  const [isFormOpen, setIsFormOpen] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);

  const isLoading = employeeLoading || requestsLoading;

  const handleCancel = async (id: string) => {
    setCancelError(null);
    try {
      await leaveService.cancelLeaveRequest(id);
      void refetchRequests();
    } catch (error) {
      setCancelError(getDbErrorMessage(error, 'Failed to cancel the leave request.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="My Leave"
        description="Request leave, track your requests, and see your current balance."
        action={
          employee && (
            <Button onClick={() => setIsFormOpen(true)}>Request leave</Button>
          )
        }
      />

      <ErrorAlert message={employeeError ?? requestsError ?? cancelError} />

      {!employeeLoading && !employee ? (
        <p className="mt-6 text-sm text-content-secondary">No employee record is linked to your account, so there is nothing to show here.</p>
      ) : (
        <>
          {!balancesLoading && balances.length > 0 && (
            <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {balances.map((balance) => {
                const type = leaveTypes.find((t) => t.id === balance.leaveTypeId);
                return (
                  <div key={balance.id} className="rounded-lg border border-border bg-surface-raised p-4">
                    <p className="text-sm font-medium text-content-primary">{type?.name ?? 'Leave'}</p>
                    <p className="mt-1 text-2xl font-bold text-content-primary">{balance.remaining}</p>
                    <p className="text-xs text-content-secondary">days remaining{balance.pending > 0 ? ` · ${balance.pending} pending` : ''}</p>
                  </div>
                );
              })}
            </div>
          )}

          <div className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
            <LeaveRequestsTable
              requests={leaveRequests}
              leaveTypes={leaveTypes}
              isLoading={isLoading}
              showSensitiveColumns
              emptyMessage="You haven't requested any leave yet."
              renderActions={(request) =>
                request.status === 'pending' ? (
                  <Button variant="ghost" onClick={() => void handleCancel(request.id)}>
                    Cancel
                  </Button>
                ) : null
              }
            />
          </div>
        </>
      )}

      {employee && (
        <LeaveRequestFormModal
          isOpen={isFormOpen}
          onClose={() => setIsFormOpen(false)}
          employeeId={employee.id}
          leaveTypes={leaveTypes}
          onSaved={() => void refetchRequests()}
        />
      )}
    </PageContainer>
  );
}
