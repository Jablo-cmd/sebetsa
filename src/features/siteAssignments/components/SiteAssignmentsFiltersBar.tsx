import type { SiteAssignmentsListFilters } from '@/features/siteAssignments/types/siteAssignment.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';

export interface SiteAssignmentsFiltersBarProps {
  filters: SiteAssignmentsListFilters;
  sites: Site[];
  onChange: (filters: SiteAssignmentsListFilters) => void;
}

export function SiteAssignmentsFiltersBar({ filters, sites, onChange }: SiteAssignmentsFiltersBarProps) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
      <select
        aria-label="Filter by site"
        value={filters.siteId ?? ''}
        onChange={(event) => onChange({ ...filters, siteId: event.target.value || undefined })}
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-56"
      >
        <option value="">All sites</option>
        {sites.map((site) => (
          <option key={site.id} value={site.id}>
            {site.name}
          </option>
        ))}
      </select>

      <select
        aria-label="Filter by current/historical"
        value={filters.when ?? ''}
        onChange={(event) =>
          onChange({ ...filters, when: (event.target.value || undefined) as SiteAssignmentsListFilters['when'] })
        }
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-40"
      >
        <option value="current">Current</option>
        <option value="historical">Historical</option>
        <option value="">All</option>
      </select>
    </div>
  );
}
