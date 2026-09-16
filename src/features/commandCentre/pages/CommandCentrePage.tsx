import { Link } from 'react-router-dom';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useCommandCentreSnapshot } from '@/features/commandCentre/hooks/useCommandCentreSnapshot';
import type { CommandCentreSnapshot } from '@/features/commandCentre/types/commandCentre.types';

function Tile({ label, value, tone, to }: { label: string; value: number; tone?: 'warning' | 'danger'; to?: string }) {
  const content = (
    <div className="rounded-xl border border-border bg-surface-raised p-4 transition-colors hover:bg-surface-sunken">
      <p className="text-xs font-medium uppercase tracking-wide text-content-tertiary">{label}</p>
      <p className={`mt-1 text-2xl font-bold ${tone === 'danger' ? 'text-danger-600' : tone === 'warning' ? 'text-warning-600' : 'text-content-primary'}`}>{value}</p>
    </div>
  );
  return to ? (
    <Link to={to} className="focus-ring block rounded-xl">
      {content}
    </Link>
  ) : (
    content
  );
}

interface TileGroup {
  title: string;
  tiles: { label: string; key: keyof CommandCentreSnapshot; warnWhenAbove?: number; dangerWhenAbove?: number; to?: string }[];
}

const GROUPS: TileGroup[] = [
  {
    title: 'Workforce',
    tiles: [
      { label: 'Scheduled today', key: 'workforceTotalScheduled' },
      { label: 'Clocked in', key: 'workforceClockedIn' },
      { label: 'Absent', key: 'workforceAbsent', warnWhenAbove: 0 },
      { label: 'Late', key: 'workforceLate', warnWhenAbove: 0 },
      { label: 'Pending GPS exceptions', key: 'workforcePendingExceptions', warnWhenAbove: 0 },
    ],
  },
  {
    title: 'Site coverage',
    tiles: [
      { label: 'Active sites', key: 'sitesTotalActive' },
      { label: 'Understaffed sites', key: 'sitesUnderstaffed', dangerWhenAbove: 0 },
      { label: 'Uncovered sites', key: 'sitesUncovered', dangerWhenAbove: 0 },
    ],
  },
  {
    title: 'Patrols',
    tiles: [
      { label: 'Active patrols', key: 'patrolsActive', to: '/patrols/oversight' },
      { label: 'Completed today', key: 'patrolsCompletedToday', to: '/patrols/oversight' },
      { label: 'Missed', key: 'patrolsMissed', warnWhenAbove: 0, to: '/patrols/oversight' },
    ],
  },
  {
    title: 'Compliance',
    tiles: [
      { label: 'Expired', key: 'complianceExpired', dangerWhenAbove: 0 },
      { label: 'Expiring soon', key: 'complianceExpiringSoon', warnWhenAbove: 0 },
    ],
  },
  {
    title: 'Incidents & tasks',
    tiles: [
      { label: 'Open incidents', key: 'incidentsOpen' },
      { label: 'Critical incidents', key: 'incidentsCritical', dangerWhenAbove: 0 },
      { label: 'Overdue incidents', key: 'incidentsOverdue', warnWhenAbove: 0 },
      { label: 'Overdue tasks', key: 'tasksOverdue', warnWhenAbove: 0 },
      { label: 'Verification pending', key: 'tasksVerificationPending' },
    ],
  },
  {
    title: 'Contracts',
    tiles: [
      { label: 'Active contracts', key: 'contractsActive' },
      { label: 'SLA breaching', key: 'contractsSlaBreaching', dangerWhenAbove: 0 },
    ],
  },
  {
    title: 'Emergencies & alerts',
    tiles: [
      { label: 'Active emergencies', key: 'emergenciesActive', dangerWhenAbove: 0, to: '/emergencies' },
      { label: 'Open alerts', key: 'alertsOpen', warnWhenAbove: 0, to: '/command-centre/alerts' },
      { label: 'Critical alerts', key: 'alertsCritical', dangerWhenAbove: 0, to: '/command-centre/alerts' },
    ],
  },
];

/**
 * SECURITY INVOKER, RLS-riding snapshot — a site_manager only ever sees the
 * sites/alerts their own RLS already scopes them to; nothing is
 * reimplemented here. Separate dashboards per role fall out of that for
 * free, not from branching UI code.
 */
export function CommandCentrePage() {
  const organization = useCurrentOrganization();
  const { snapshot, isLoading, error } = useCommandCentreSnapshot(organization?.id);

  if (!organization) return <NoActiveOrganizationNotice resource="the command centre" />;

  return (
    <PageContainer>
      <PageHeader title="Command Centre" description="Who's working, is every site covered, and what needs attention right now." />
      <ErrorAlert message={error} />

      {isLoading || !snapshot ? (
        <LoadingBlock label="Loading the command centre snapshot…" />
      ) : (
        <div className="flex flex-col gap-6">
          {GROUPS.map((group) => (
            <div key={group.title}>
              <h2 className="mb-2 text-sm font-semibold text-content-secondary">{group.title}</h2>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
                {group.tiles.map((tile) => {
                  const value = snapshot[tile.key];
                  const tone = tile.dangerWhenAbove !== undefined && value > tile.dangerWhenAbove ? 'danger' : tile.warnWhenAbove !== undefined && value > tile.warnWhenAbove ? 'warning' : undefined;
                  return <Tile key={tile.key} label={tile.label} value={value} tone={tone} to={tile.to} />;
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </PageContainer>
  );
}
