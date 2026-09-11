import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Client, Region } from '@/features/orgStructure/types/orgStructure.types';

export interface ClientsTableProps {
  clients: Client[];
  regions: Region[];
}

const STATUS_CLASSES: Record<Client['status'], string> = {
  active: 'text-success-500',
  inactive: 'text-content-tertiary',
  onboarding: 'text-warning-600 dark:text-warning-500',
  offboarded: 'text-content-tertiary',
};

export function ClientsTable({ clients, regions }: ClientsTableProps) {
  if (clients.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No clients match your filters.
      </div>
    );
  }

  const regionName = (regionId: string | null) => regions.find((r) => r.id === regionId)?.name ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[640px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Client
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Region
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Industry
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {clients.map((client) => (
            <tr key={client.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                <Link to={`/clients/${client.id}`} className="focus-ring rounded hover:text-brand-600">
                  {client.name}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">{regionName(client.regionId)}</td>
              <td className="px-4 py-3 text-content-secondary">{client.industry ?? '—'}</td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[client.status])}>{client.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
