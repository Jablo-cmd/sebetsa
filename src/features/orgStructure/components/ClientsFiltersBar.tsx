import { SearchIcon } from '@/components/ui/icons';
import type { ClientsListFilters, EntityStatus, Region } from '@/features/orgStructure/types/orgStructure.types';

export interface ClientsFiltersBarProps {
  filters: ClientsListFilters;
  regions: Region[];
  onChange: (filters: ClientsListFilters) => void;
}

const STATUS_OPTIONS: { value: EntityStatus; label: string }[] = [
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
  { value: 'onboarding', label: 'Onboarding' },
  { value: 'offboarded', label: 'Offboarded' },
];

export function ClientsFiltersBar({ filters, regions, onChange }: ClientsFiltersBarProps) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
      <div className="relative flex-1">
        <SearchIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-content-tertiary" />
        <input
          type="search"
          value={filters.search ?? ''}
          onChange={(event) => onChange({ ...filters, search: event.target.value })}
          placeholder="Search by name or industry…"
          aria-label="Search clients"
          className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised pl-9 pr-3.5 text-sm text-content-primary placeholder:text-content-tertiary"
        />
      </div>

      <select
        aria-label="Filter by region"
        value={filters.regionId ?? ''}
        onChange={(event) => onChange({ ...filters, regionId: event.target.value || undefined })}
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-48"
      >
        <option value="">All regions</option>
        {regions.map((region) => (
          <option key={region.id} value={region.id}>
            {region.name}
          </option>
        ))}
      </select>

      <select
        aria-label="Filter by status"
        value={filters.status ?? ''}
        onChange={(event) => onChange({ ...filters, status: (event.target.value || undefined) as EntityStatus | undefined })}
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
