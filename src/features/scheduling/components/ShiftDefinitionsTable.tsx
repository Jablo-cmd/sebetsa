import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { ShiftDefinition } from '@/features/scheduling/types/scheduling.types';

export interface ShiftDefinitionsTableProps {
  shiftDefinitions: ShiftDefinition[];
  canManage: boolean;
  onEdit: (definition: ShiftDefinition) => void;
  onToggleActive: (definition: ShiftDefinition) => void;
}

const STATUS_CLASSES: Record<ShiftDefinition['status'], string> = {
  active: 'text-success-500',
  inactive: 'text-content-tertiary',
  onboarding: 'text-warning-600 dark:text-warning-500',
  offboarded: 'text-content-tertiary',
};

export function ShiftDefinitionsTable({ shiftDefinitions, canManage, onEdit, onToggleActive }: ShiftDefinitionsTableProps) {
  if (shiftDefinitions.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No shift definitions yet.
      </div>
    );
  }

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[640px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Name
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Time
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Break
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
          {shiftDefinitions.map((definition) => (
            <tr key={definition.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">{definition.name}</td>
              <td className="px-4 py-3 text-content-secondary">
                {definition.startTime.slice(0, 5)}–{definition.endTime.slice(0, 5)}
                {definition.isOvernight && (
                  <span className="ml-1.5 rounded-full bg-surface-sunken px-2 py-0.5 text-xs text-content-tertiary">
                    overnight
                  </span>
                )}
              </td>
              <td className="px-4 py-3 text-content-secondary">
                {definition.breakMinutes > 0 ? `${definition.breakMinutes} min` : '—'}
              </td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[definition.status])}>{definition.status}</td>
              {canManage && (
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-1.5">
                    <button
                      type="button"
                      onClick={() => onEdit(definition)}
                      className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      onClick={() => onToggleActive(definition)}
                      className={
                        definition.status === 'active'
                          ? 'focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50'
                          : 'focus-ring rounded-md px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50 dark:hover:bg-brand-500/10'
                      }
                    >
                      {definition.status === 'active' ? 'Archive' : 'Restore'}
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
