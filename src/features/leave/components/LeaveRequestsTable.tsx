import type { ReactNode } from 'react';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import type { LeaveRequest, LeaveRequestSummary, LeaveType } from '@/features/leave/types/leave.types';
import type { LeaveStatusEnum } from '@/lib/dbTypes';

const STATUS_LABEL: Record<string, string> = {
  pending: 'Pending',
  approved: 'Approved',
  rejected: 'Rejected',
  cancelled: 'Cancelled',
  revoked: 'Revoked',
};

const STATUS_TONES: Record<LeaveStatusEnum, StatusTone> = {
  pending: 'warning',
  approved: 'success',
  rejected: 'danger',
  cancelled: 'neutral',
  revoked: 'neutral',
};

export interface LeaveRequestsTableProps {
  requests: (LeaveRequest | LeaveRequestSummary)[];
  leaveTypes: LeaveType[];
  isLoading: boolean;
  emptyMessage: string;
  /** Shows reason/decision notes columns — only pass true when the caller
   * actually has them (i.e. a full LeaveRequest, not a summary projection). */
  showSensitiveColumns?: boolean;
  renderActions?: (request: LeaveRequest | LeaveRequestSummary) => ReactNode;
}

export function LeaveRequestsTable({
  requests,
  leaveTypes,
  isLoading,
  emptyMessage,
  showSensitiveColumns = false,
  renderActions,
}: LeaveRequestsTableProps) {
  const leaveTypeName = (id: string) => leaveTypes.find((t) => t.id === id)?.name ?? '—';

  if (isLoading) {
    return <p className="py-6 text-center text-sm text-content-secondary">Loading…</p>;
  }

  if (requests.length === 0) {
    return <p className="py-6 text-center text-sm text-content-secondary">{emptyMessage}</p>;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase text-content-secondary">
            <th className="px-3 py-2">Leave type</th>
            <th className="px-3 py-2">Dates</th>
            <th className="px-3 py-2">Duration</th>
            <th className="px-3 py-2">Status</th>
            {showSensitiveColumns && <th className="px-3 py-2">Reason</th>}
            {renderActions && <th className="px-3 py-2 text-right">Actions</th>}
          </tr>
        </thead>
        <tbody>
          {requests.map((request) => (
            <tr key={request.id} className="border-b border-border last:border-0">
              <td className="px-3 py-2.5">{leaveTypeName(request.leaveTypeId)}</td>
              <td className="px-3 py-2.5">
                {request.startDate === request.endDate ? request.startDate : `${request.startDate} – ${request.endDate}`}
              </td>
              <td className="px-3 py-2.5">{request.isHalfDay ? `Half day (${request.halfDayPeriod?.toUpperCase()})` : 'Full day'}</td>
              <td className="px-3 py-2.5">
                <StatusBadge label={STATUS_LABEL[request.status] ?? request.status} tone={STATUS_TONES[request.status]} />
              </td>
              {showSensitiveColumns && <td className="px-3 py-2.5 text-content-secondary">{'reason' in request ? request.reason ?? '—' : '—'}</td>}
              {renderActions && <td className="px-3 py-2.5 text-right">{renderActions(request)}</td>}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
