import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useLeaveRequests } from '@/features/leave/hooks/useLeaveRequests';
import { useLeaveTypes } from '@/features/leave/hooks/useLeaveTypes';
import { LeaveRequestsTable } from '@/features/leave/components/LeaveRequestsTable';
import { LeaveApprovalDialog } from '@/features/leave/components/LeaveApprovalDialog';
import type { LeaveRequest } from '@/features/leave/types/leave.types';

const STATUS_FILTERS = [
  { value: 'pending', label: 'Pending approval' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'revoked', label: 'Revoked' },
] as const;

/** Approval queue for leave.approve holders — supervisor/site_manager see
 * nothing here today (no leave.approve), per the existing role/permission
 * scaffold in rolePermissions.ts; this page is not the place to change that. */
export function LeaveManagementPage() {
  const organization = useCurrentOrganization();
  const [statusFilter, setStatusFilter] = useState<(typeof STATUS_FILTERS)[number]['value']>('pending');
  const { leaveRequests, isLoading, error, refetch } = useLeaveRequests(organization?.id, { status: statusFilter });
  const { leaveTypes } = useLeaveTypes(organization?.id);
  const [selectedRequest, setSelectedRequest] = useState<LeaveRequest | null>(null);

  if (!organization) return <NoActiveOrganizationNotice resource="leave" />;

  return (
    <PageContainer>
      <PageHeader title="Leave Management" description="Review and decide on employee leave requests." />

      <ErrorAlert message={error} />

      <div className="mt-4 flex flex-wrap gap-2">
        {STATUS_FILTERS.map((filter) => (
          <button
            key={filter.value}
            type="button"
            onClick={() => setStatusFilter(filter.value)}
            className={`focus-ring rounded-full px-3 py-1.5 text-sm font-medium ${
              statusFilter === filter.value
                ? 'bg-brand-600 text-white'
                : 'bg-surface-raised text-content-secondary hover:bg-surface-sunken'
            }`}
          >
            {filter.label}
          </button>
        ))}
      </div>

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <LeaveRequestsTable
          requests={leaveRequests}
          leaveTypes={leaveTypes}
          isLoading={isLoading}
          showSensitiveColumns
          emptyMessage="No leave requests in this status."
          renderActions={(request) =>
            request.status === 'pending' || request.status === 'approved' ? (
              <Button variant="ghost" onClick={() => setSelectedRequest(request as LeaveRequest)}>
                Review
              </Button>
            ) : null
          }
        />
      </div>

      <LeaveApprovalDialog
        isOpen={selectedRequest !== null}
        onClose={() => setSelectedRequest(null)}
        request={selectedRequest}
        leaveTypes={leaveTypes}
        onDecided={() => void refetch()}
      />
    </PageContainer>
  );
}
