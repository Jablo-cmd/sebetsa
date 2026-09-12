import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { Link } from 'react-router-dom';
import type { Employee, EmploymentStatus, Department, Position } from '@/features/employees/types/employee.types';

export interface EmployeesTableProps {
  employees: Employee[];
  departments: Department[];
  positions: Position[];
  canManage: boolean;
  onEdit: (employee: Employee) => void;
  onTerminate: (employee: Employee) => void;
  onReactivate: (employee: Employee) => void;
}

const STATUS_TONES: Record<EmploymentStatus, StatusTone> = {
  active: 'success',
  on_leave: 'info',
  suspended: 'danger',
  terminated: 'neutral',
};

export function EmployeesTable({
  employees,
  departments,
  positions,
  canManage,
  onEdit,
  onTerminate,
  onReactivate,
}: EmployeesTableProps) {
  if (employees.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No employees match your filters.
      </div>
    );
  }

  const departmentName = (departmentId: string | null) =>
    departments.find((department) => department.id === departmentId)?.name ?? '—';
  const positionTitle = (positionId: string | null) =>
    positions.find((position) => position.id === positionId)?.title ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Name
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Department
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Position
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
            <th scope="col" className="px-4 py-3 text-right font-medium">
              Actions
            </th>
          </tr>
        </thead>
        <tbody>
          {employees.map((employee) => (
            <tr key={employee.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3">
                <Link
                  to={`/employees/${employee.id}`}
                  className="focus-ring rounded font-medium text-content-primary hover:text-brand-600"
                >
                  {employee.firstName} {employee.lastName}
                </Link>
                <p className="text-content-tertiary">{employee.employeeNumber}</p>
              </td>
              <td className="px-4 py-3 text-content-secondary">{departmentName(employee.departmentId)}</td>
              <td className="px-4 py-3 text-content-secondary">{positionTitle(employee.positionId)}</td>
              <td className="px-4 py-3">
                <StatusBadge label={employee.employmentStatus.replace(/_/g, ' ')} tone={STATUS_TONES[employee.employmentStatus]} />
              </td>
              <td className="px-4 py-3">
                <div className="flex justify-end gap-1.5">
                  <Link
                    to={`/employees/${employee.id}`}
                    className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                  >
                    View
                  </Link>
                  {canManage && (
                    <>
                      <button
                        type="button"
                        onClick={() => onEdit(employee)}
                        className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                      >
                        Edit
                      </button>
                      {employee.employmentStatus === 'terminated' ? (
                        <button
                          type="button"
                          onClick={() => onReactivate(employee)}
                          className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50 dark:hover:bg-brand-500/10"
                        >
                          Reactivate
                        </button>
                      ) : (
                        <button
                          type="button"
                          onClick={() => onTerminate(employee)}
                          className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50"
                        >
                          Terminate
                        </button>
                      )}
                    </>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
