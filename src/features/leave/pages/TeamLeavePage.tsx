import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useTeamLeave } from '@/features/leave/hooks/useTeamLeave';
import { useLeaveTypes } from '@/features/leave/hooks/useLeaveTypes';
import { LeaveRequestsTable } from '@/features/leave/components/LeaveRequestsTable';

/** Read-only staffing-impact view, reached by anyone holding leave.view
 * (both the nav entry and the /leave/team route guard use that permission —
 * see navigation.ts for why a narrower gate isn't used). For a plain
 * employee this returns just their own row via the same RLS clause My
 * Leave uses; for a broader role (site_manager and up) it returns the
 * tenant's leave requests, field-projected — no reason/decision-notes
 * columns (see useTeamLeave/getLeaveRequestsSummary). */
export function TeamLeavePage() {
  const organization = useCurrentOrganization();
  const { leaveRequests, isLoading, error } = useTeamLeave(organization?.id);
  const { leaveTypes } = useLeaveTypes(organization?.id);

  if (!organization) return <NoActiveOrganizationNotice resource="leave" />;

  return (
    <PageContainer>
      <PageHeader title="Team Leave" description="Who is on leave, and when — for staffing awareness." />

      <ErrorAlert message={error} />

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <LeaveRequestsTable requests={leaveRequests} leaveTypes={leaveTypes} isLoading={isLoading} emptyMessage="No leave requests to show." />
      </div>
    </PageContainer>
  );
}
