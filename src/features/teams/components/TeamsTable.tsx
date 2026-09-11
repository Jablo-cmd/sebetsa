import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Team } from '@/features/teams/types/team.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';

export interface TeamsTableProps {
  teams: Team[];
  sites: Site[];
}

const STATUS_CLASSES: Record<Team['status'], string> = {
  active: 'text-success-500',
  inactive: 'text-content-tertiary',
  onboarding: 'text-warning-600 dark:text-warning-500',
  offboarded: 'text-content-tertiary',
};

export function TeamsTable({ teams, sites }: TeamsTableProps) {
  if (teams.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No teams match your filters.
      </div>
    );
  }

  const siteName = (siteId: string | null) => sites.find((s) => s.id === siteId)?.name ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[560px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Team
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Site
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {teams.map((team) => (
            <tr key={team.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                <Link to={`/teams/${team.id}`} className="focus-ring rounded hover:text-brand-600">
                  {team.name}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">{siteName(team.siteId)}</td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[team.status])}>{team.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
