import { cn } from '@/lib/cn';
import type { Organization } from '@/types/organization.types';

export interface OrganizationsTableProps {
  organizations: Organization[];
  activeOrganizationId: string | null;
  onSwitch: (organization: Organization) => void;
  switchingId: string | null;
}

const STATUS_CLASSES: Record<Organization['status'], string> = {
  active: 'text-success-500',
  pending: 'text-warning-600 dark:text-warning-500',
  inactive: 'text-content-tertiary',
  suspended: 'text-danger-600',
};

export function OrganizationsTable({
  organizations,
  activeOrganizationId,
  onSwitch,
  switchingId,
}: OrganizationsTableProps) {
  if (organizations.length === 0) {
    return (
      <p className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No organizations have been created yet.
      </p>
    );
  }

  return (
    <div className="overflow-hidden rounded-card border border-border">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-border bg-surface-raised text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Organization
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Industry
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
            <th scope="col" className="px-4 py-3 text-right font-medium">
              Action
            </th>
          </tr>
        </thead>
        <tbody>
          {organizations.map((organization) => {
            const isActive = organization.id === activeOrganizationId;
            return (
              <tr key={organization.id} className="border-b border-border last:border-0">
                <td className="px-4 py-3 font-medium text-content-primary">{organization.name}</td>
                <td className="px-4 py-3 text-content-secondary">{organization.industry ?? '—'}</td>
                <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[organization.status])}>
                  {organization.status}
                </td>
                <td className="px-4 py-3 text-right">
                  {isActive ? (
                    <span className="text-xs font-semibold uppercase tracking-wide text-brand-600 dark:text-brand-300">
                      Active
                    </span>
                  ) : (
                    <button
                      type="button"
                      onClick={() => onSwitch(organization)}
                      disabled={switchingId === organization.id}
                      className="focus-ring rounded-md border border-border-strong px-3 py-1.5 text-xs font-medium text-content-secondary hover:bg-surface-sunken disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      {switchingId === organization.id ? 'Switching…' : 'Switch to this organization'}
                    </button>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
