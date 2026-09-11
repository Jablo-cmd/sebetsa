import { SearchIcon } from '@/components/ui/icons';
import type { ContractsListFilters, ContractStatus, Client } from '@/features/orgStructure/types/orgStructure.types';

export interface ContractsFiltersBarProps {
  filters: ContractsListFilters;
  clients: Client[];
  onChange: (filters: ContractsListFilters) => void;
}

const STATUS_OPTIONS: { value: ContractStatus; label: string }[] = [
  { value: 'draft', label: 'Draft' },
  { value: 'active', label: 'Active' },
  { value: 'expired', label: 'Expired' },
  { value: 'terminated', label: 'Terminated' },
];

export function ContractsFiltersBar({ filters, clients, onChange }: ContractsFiltersBarProps) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
      <div className="relative flex-1">
        <SearchIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-content-tertiary" />
        <input
          type="search"
          value={filters.search ?? ''}
          onChange={(event) => onChange({ ...filters, search: event.target.value })}
          placeholder="Search by contract number…"
          aria-label="Search contracts"
          className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised pl-9 pr-3.5 text-sm text-content-primary placeholder:text-content-tertiary"
        />
      </div>

      <select
        aria-label="Filter by client"
        value={filters.clientId ?? ''}
        onChange={(event) => onChange({ ...filters, clientId: event.target.value || undefined })}
        className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-48"
      >
        <option value="">All clients</option>
        {clients.map((client) => (
          <option key={client.id} value={client.id}>
            {client.name}
          </option>
        ))}
      </select>

      <select
        aria-label="Filter by status"
        value={filters.status ?? ''}
        onChange={(event) => onChange({ ...filters, status: (event.target.value || undefined) as ContractStatus | undefined })}
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
