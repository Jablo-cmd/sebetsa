import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useSiteAssignments } from '@/features/siteAssignments/hooks/useSiteAssignments';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { siteAssignmentService } from '@/features/siteAssignments/services/siteAssignmentService';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { SiteAssignmentsFiltersBar } from '@/features/siteAssignments/components/SiteAssignmentsFiltersBar';
import { SiteAssignmentsTable } from '@/features/siteAssignments/components/SiteAssignmentsTable';
import { SiteAssignmentFormModal } from '@/features/siteAssignments/components/SiteAssignmentFormModal';
import type { SiteAssignment } from '@/features/siteAssignments/types/siteAssignment.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function SiteAssignmentsPage() {
  const { can } = usePermissions();
  const canManage = can('site_assignment.manage');
  const organization = useCurrentOrganization();
  const { assignments, isLoading, error, filters, setFilters, refetch } = useSiteAssignments(organization?.id);
  const { sites } = useAllSites(organization?.id);

  const [employees, setEmployees] = useState<Map<string, EmployeeCandidate>>(new Map());
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [editingAssignment, setEditingAssignment] = useState<SiteAssignment | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    const ids = [...new Set(assignments.map((a) => a.employeeId))];
    if (ids.length === 0) {
      setEmployees(new Map());
      return;
    }
    let cancelled = false;
    void employeeService.getEmployeeCandidatesByIds(ids).then((results) => {
      if (!cancelled) setEmployees(new Map(results.map((e) => [e.id, e])));
    });
    return () => {
      cancelled = true;
    };
  }, [assignments]);

  const handleEnd = async (assignment: SiteAssignment) => {
    setActionError(null);
    try {
      await siteAssignmentService.endAssignment(assignment.id);
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to end site assignment.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Site Assignments"
        description="Which employees are currently — or were previously — assigned to work at which site."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)}>
                Assign employee
              </Button>
            </div>
          )
        }
      />

      {organization && <SiteAssignmentsFiltersBar filters={filters} sites={sites} onChange={setFilters} />}

      <ErrorAlert message={error ?? actionError} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="site assignments" />
      ) : isLoading ? (
        <LoadingBlock label="Loading site assignments…" />
      ) : (
        <SiteAssignmentsTable
          assignments={assignments}
          sites={sites}
          employees={employees}
          canManage={canManage}
          onEdit={setEditingAssignment}
          onEnd={(assignment) => void handleEnd(assignment)}
        />
      )}

      {organization && (
        <SiteAssignmentFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          sites={sites}
          onSaved={() => void refetch()}
        />
      )}
      {editingAssignment && organization && (
        <SiteAssignmentFormModal
          isOpen={Boolean(editingAssignment)}
          onClose={() => setEditingAssignment(null)}
          tenantId={organization.id}
          assignment={editingAssignment}
          sites={sites}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
