import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Site, Client, Region } from '@/features/orgStructure/types/orgStructure.types';

export interface SitesTableProps {
  sites: Site[];
  clients: Client[];
  regions: Region[];
}

const STATUS_CLASSES: Record<Site['status'], string> = {
  active: 'text-success-500',
  inactive: 'text-content-tertiary',
  onboarding: 'text-warning-600 dark:text-warning-500',
  offboarded: 'text-content-tertiary',
};

export function SitesTable({ sites, clients, regions }: SitesTableProps) {
  if (sites.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No sites match your filters.
      </div>
    );
  }

  const clientName = (clientId: string) => clients.find((c) => c.id === clientId)?.name ?? '—';
  const regionName = (regionId: string | null) => regions.find((r) => r.id === regionId)?.name ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Site
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Client
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Region
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {sites.map((site) => (
            <tr key={site.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3">
                <Link to={`/sites/${site.id}`} className="focus-ring rounded font-medium text-content-primary hover:text-brand-600">
                  {site.name}
                </Link>
                {site.address && <p className="text-content-tertiary">{site.address}</p>}
              </td>
              <td className="px-4 py-3 text-content-secondary">{clientName(site.clientId)}</td>
              <td className="px-4 py-3 text-content-secondary">{regionName(site.regionId)}</td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[site.status])}>{site.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
