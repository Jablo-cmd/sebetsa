import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Shift } from '@/features/scheduling/types/scheduling.types';

export interface ScheduleGridEmployee {
  id: string;
  firstName: string;
  lastName: string;
}

export interface ScheduleWeekGridProps {
  days: Date[];
  employees: ScheduleGridEmployee[];
  shifts: Shift[];
  canManage: boolean;
  onCreateShift: (employeeId: string, date: Date) => void;
  onEditShift: (shift: Shift) => void;
}

function dateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

const STATUS_CLASSES: Record<Shift['status'], string> = {
  scheduled: 'border-brand-400 bg-brand-50 text-brand-700 dark:bg-brand-500/10 dark:text-brand-300',
  confirmed: 'border-success-500/40 bg-success-500/15 text-success-500',
  cancelled: 'border-border-strong bg-surface-sunken text-content-tertiary line-through',
  completed: 'border-border-strong bg-surface-sunken text-content-secondary',
};

export function ScheduleWeekGrid({ days, employees, shifts, canManage, onCreateShift, onEditShift }: ScheduleWeekGridProps) {
  if (employees.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No employees to schedule at this site yet — assign employees to the site first, or create a shift for anyone via Site
        Assignments.
      </div>
    );
  }

  // A shift is placed on every calendar day its window touches, so an
  // overnight shift shows on both its start day and its end day.
  const shiftsFor = (employeeId: string, day: Date): Shift[] => {
    const key = dateKey(day);
    return shifts.filter((shift) => {
      if (shift.employeeId !== employeeId) return false;
      const startKey = dateKey(new Date(shift.startsAt));
      const endKey = dateKey(new Date(shift.endsAt));
      return key === startKey || key === endKey;
    });
  };

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[900px] table-fixed text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="w-40 px-4 py-3 font-medium">
              Employee
            </th>
            {days.map((day) => (
              <th key={dateKey(day)} scope="col" className="px-2 py-3 text-center font-medium">
                {day.toLocaleDateString('en-ZA', { weekday: 'short' })}
                <div className="font-normal normal-case text-content-tertiary">
                  {day.toLocaleDateString('en-ZA', { day: '2-digit', month: 'short' })}
                </div>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {employees.map((employee) => (
            <tr key={employee.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                {employee.firstName} {employee.lastName}
              </td>
              {days.map((day) => {
                const cellShifts = shiftsFor(employee.id, day);
                return (
                  <td key={dateKey(day)} className="p-1.5 align-top">
                    <div className="flex min-h-[3rem] flex-col gap-1">
                      {cellShifts.map((shift) => (
                        <button
                          key={shift.id}
                          type="button"
                          onClick={() => canManage && onEditShift(shift)}
                          className={cn(
                            'focus-ring rounded-md border px-1.5 py-1 text-left text-xs font-medium',
                            STATUS_CLASSES[shift.status],
                            !canManage && 'cursor-default',
                          )}
                        >
                          {new Date(shift.startsAt).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })}
                          {'–'}
                          {new Date(shift.endsAt).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })}
                        </button>
                      ))}
                      {canManage && (
                        <button
                          type="button"
                          onClick={() => onCreateShift(employee.id, day)}
                          className="focus-ring rounded-md border border-dashed border-border-strong px-1.5 py-1 text-xs text-content-tertiary hover:border-brand-400 hover:text-brand-600"
                        >
                          + Add
                        </button>
                      )}
                    </div>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
