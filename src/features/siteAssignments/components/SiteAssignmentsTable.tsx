import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import type { SiteAssignment } from '@/features/siteAssignments/types/siteAssignment.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';

export interface SiteAssignmentsTableProps {
  assignments: SiteAssignment[];
  sites: Site[];
  employees: Map<string, EmployeeCandidate>;
  canManage: boolean;
  onEdit: (assignment: SiteAssignment) => void;
  onEnd: (assignment: SiteAssignment) => void;
}

export function SiteAssignmentsTable({ assignments, sites, employees, canManage, onEdit, onEnd }: SiteAssignmentsTableProps) {
  if (assignments.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No site assignments match your filters.
      </div>
    );
  }

  const siteName = (siteId: string) => sites.find((s) => s.id === siteId)?.name ?? '—';
  const employeeName = (employeeId: string) => {
    const employee = employees.get(employeeId);
    return employee ? `${employee.firstName} ${employee.lastName}` : '—';
  };

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Employee
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Site
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Role
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Start
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              End
            </th>
            {canManage && (
              <th scope="col" className="px-4 py-3 text-right font-medium">
                Actions
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {assignments.map((assignment) => (
            <tr key={assignment.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                <Link to={`/employees/${assignment.employeeId}`} className="focus-ring rounded hover:text-brand-600">
                  {employeeName(assignment.employeeId)}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">
                <Link to={`/sites/${assignment.siteId}`} className="focus-ring rounded hover:text-brand-600">
                  {siteName(assignment.siteId)}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">{assignment.roleOnSite ?? '—'}</td>
              <td className="px-4 py-3 text-content-secondary">{assignment.startDate}</td>
              <td className="px-4 py-3 text-content-secondary">{assignment.endDate ?? '—'}</td>
              {canManage && (
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-1.5">
                    <button
                      type="button"
                      onClick={() => onEdit(assignment)}
                      className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                    >
                      Edit
                    </button>
                    {!assignment.endDate && (
                      <button
                        type="button"
                        onClick={() => onEnd(assignment)}
                        className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50"
                      >
                        End
                      </button>
                    )}
                  </div>
                </td>
              )}
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
