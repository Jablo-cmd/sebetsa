import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import type { Department } from '@/features/employees/types/employee.types';

export interface DepartmentsTableProps {
  departments: Department[];
  canManage: boolean;
  onEdit: (department: Department) => void;
  onDelete: (department: Department) => void;
}

export function DepartmentsTable({ departments, canManage, onEdit, onDelete }: DepartmentsTableProps) {
  if (departments.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No departments match your filters.
      </div>
    );
  }

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[400px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Name
            </th>
            {canManage && (
              <th scope="col" className="px-4 py-3 text-right font-medium">
                Actions
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {departments.map((department) => (
            <tr key={department.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">{department.name}</td>
              {canManage && (
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-1.5">
                    <button
                      type="button"
                      onClick={() => onEdit(department)}
                      className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      onClick={() => onDelete(department)}
                      className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50"
                    >
                      Delete
                    </button>
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
