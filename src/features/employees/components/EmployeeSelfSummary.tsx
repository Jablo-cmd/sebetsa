import type { Employee } from '@/features/employees/types/employee.types';

export interface EmployeeSelfSummaryProps {
  employee: Employee;
}

/** Read-only self-view summary of the caller's own employee record — no manage actions, unlike EmployeeProfilePage. */
export function EmployeeSelfSummary({ employee }: EmployeeSelfSummaryProps) {
  return (
    <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-4">
          <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-brand-600 text-lg font-semibold text-white">
            {employee.firstName[0]}
            {employee.lastName[0]}
          </span>
          <div>
            <h2 className="text-xl font-bold text-content-primary">
              {employee.firstName} {employee.lastName}
            </h2>
            <p className="text-sm text-content-secondary">{employee.employeeNumber}</p>
          </div>
        </div>
        <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
          {employee.employmentStatus.replace(/_/g, ' ')}
        </span>
      </div>

      <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Employment type</dt>
          <dd className="mt-1 text-sm capitalize text-content-primary">
            {employee.employmentType?.replace(/_/g, ' ') ?? '—'}
          </dd>
        </div>
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Start date</dt>
          <dd className="mt-1 text-sm text-content-primary">{employee.employmentStartDate}</dd>
        </div>
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Email</dt>
          <dd className="mt-1 text-sm text-content-primary">{employee.email ?? '—'}</dd>
        </div>
        <div>
          <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Phone</dt>
          <dd className="mt-1 text-sm text-content-primary">{employee.phone ?? '—'}</dd>
        </div>
      </dl>
    </div>
  );
}
