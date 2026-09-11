import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Position, Department } from '@/features/employees/types/employee.types';

export interface PositionsTableProps {
  positions: Position[];
  departments: Department[];
  canManage: boolean;
  onEdit: (position: Position) => void;
  onToggleActive: (position: Position) => void;
}

const STATUS_CLASSES: Record<Position['status'], string> = {
  active: 'text-success-500',
  inactive: 'text-content-tertiary',
  onboarding: 'text-warning-600 dark:text-warning-500',
  offboarded: 'text-content-tertiary',
};

export function PositionsTable({ positions, departments, canManage, onEdit, onToggleActive }: PositionsTableProps) {
  if (positions.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No positions match your filters.
      </div>
    );
  }

  const departmentName = (departmentId: string | null) =>
    departments.find((department) => department.id === departmentId)?.name ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[560px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Title
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Department
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
            {canManage && (
              <th scope="col" className="px-4 py-3 text-right font-medium">
                Actions
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {positions.map((position) => (
            <tr key={position.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">{position.title}</td>
              <td className="px-4 py-3 text-content-secondary">{departmentName(position.departmentId)}</td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[position.status])}>{position.status}</td>
              {canManage && (
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-1.5">
                    <button
                      type="button"
                      onClick={() => onEdit(position)}
                      className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      onClick={() => onToggleActive(position)}
                      className={
                        position.status === 'active'
                          ? 'focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50'
                          : 'focus-ring rounded-md px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50 dark:hover:bg-brand-500/10'
                      }
                    >
                      {position.status === 'active' ? 'Archive' : 'Restore'}
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
