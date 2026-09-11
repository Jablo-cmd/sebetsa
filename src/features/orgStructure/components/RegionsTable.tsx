import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Region } from '@/features/orgStructure/types/orgStructure.types';

export interface RegionsTableProps {
  regions: Region[];
  canManage: boolean;
  onEdit: (region: Region) => void;
  onToggleActive: (region: Region) => void;
}

const STATUS_CLASSES: Record<Region['status'], string> = {
  active: 'text-success-500',
  inactive: 'text-content-tertiary',
  onboarding: 'text-warning-600 dark:text-warning-500',
  offboarded: 'text-content-tertiary',
};

export function RegionsTable({ regions, canManage, onEdit, onToggleActive }: RegionsTableProps) {
  if (regions.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No regions match your filters.
      </div>
    );
  }

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[560px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Name
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Code
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
          {regions.map((region) => (
            <tr key={region.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                <Link to={`/regions/${region.id}`} className="focus-ring rounded hover:text-brand-600">
                  {region.name}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">{region.code ?? '—'}</td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[region.status])}>{region.status}</td>
              {canManage && (
                <td className="px-4 py-3">
                  <div className="flex justify-end gap-1.5">
                    <button
                      type="button"
                      onClick={() => onEdit(region)}
                      className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-content-secondary hover:bg-surface-sunken hover:text-content-primary"
                    >
                      Edit
                    </button>
                    <button
                      type="button"
                      onClick={() => onToggleActive(region)}
                      className={
                        region.status === 'active'
                          ? 'focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50'
                          : 'focus-ring rounded-md px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50 dark:hover:bg-brand-500/10'
                      }
                    >
                      {region.status === 'active' ? 'Archive' : 'Restore'}
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
