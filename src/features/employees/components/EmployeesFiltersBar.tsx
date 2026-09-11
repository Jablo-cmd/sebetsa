import { SearchIcon } from '@/components/ui/icons';
import type { EmployeesListFilters, EmploymentStatus, Department, Position } from '@/features/employees/types/employee.types';

export interface EmployeesFiltersBarProps {
  filters: EmployeesListFilters;
  departments: Department[];
  positions: Position[];
  onChange: (filters: EmployeesListFilters) => void;
}

const STATUS_OPTIONS: { value: EmploymentStatus; label: string }[] = [
  { value: 'active', label: 'Active' },
  { value: 'on_leave', label: 'On leave' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'terminated', label: 'Terminated' },
];

export function EmployeesFiltersBar({ filters, departments, positions, onChange }: EmployeesFiltersBarProps) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
      <div className="relative flex-1">
        <SearchIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-content-tertiary" />
        <input
          type="search"
          value={filters.search ?? ''}
          onChange={(event) => onChange({ ...filters, search: event.target.value })}
          placeholder="Search by name or employee number…"
          aria-label="Search employees"
          className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised pl-9 pr-3.5 text-sm text-content-primary placeholder:text-content-tertiary"
        />
      </div>

      <select
        aria-label="Filter by department"
        value={filters.departmentId ?? ''}
        onChange={(event) => onChange({ ...filters, departmentId: event.target.value || undefined })}
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-48"
      >
        <option value="">All departments</option>
        {departments.map((department) => (
          <option key={department.id} value={department.id}>
            {department.name}
          </option>
        ))}
      </select>

      <select
        aria-label="Filter by position"
        value={filters.positionId ?? ''}
        onChange={(event) => onChange({ ...filters, positionId: event.target.value || undefined })}
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-48"
      >
        <option value="">All positions</option>
        {positions.map((position) => (
          <option key={position.id} value={position.id}>
            {position.title}
          </option>
        ))}
      </select>

      <select
        aria-label="Filter by employment status"
        value={filters.employmentStatus ?? ''}
        onChange={(event) =>
          onChange({ ...filters, employmentStatus: (event.target.value || undefined) as EmploymentStatus | undefined })
        }
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-40"
      >
        <option value="">All statuses</option>
        {STATUS_OPTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </div>
  );
}
