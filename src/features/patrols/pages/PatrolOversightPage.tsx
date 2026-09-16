import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { usePatrolSummary } from '@/features/patrols/hooks/usePatrolSummary';
import type { PatrolRunStatus } from '@/features/patrols/types/patrol.types';
import type { StatusTone } from '@/components/ui/StatusBadge';

const RUN_STATUS_LABEL: Record<PatrolRunStatus, string> = {
  in_progress: 'In progress',
  completed: 'Completed',
  incomplete: 'Incomplete',
  abandoned: 'Abandoned',
};

const RUN_STATUS_TONE: Record<PatrolRunStatus, StatusTone> = {
  in_progress: 'info',
  completed: 'success',
  incomplete: 'warning',
  abandoned: 'danger',
};

function StatCard({ label, value, tone }: { label: string; value: number; tone?: 'warning' | 'danger' }) {
  return (
    <div className="rounded-xl border border-border bg-surface-raised p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-content-tertiary">{label}</p>
      <p className={`mt-1 text-2xl font-bold ${tone === 'danger' ? 'text-danger-600' : tone === 'warning' ? 'text-warning-600' : 'text-content-primary'}`}>{value}</p>
    </div>
  );
}

/** Real, live aggregate figures over the last 7 days (get_patrol_summary()) — no hardcoded stats, RLS-scoped to the caller's own tenant regardless of role tier. */
export function PatrolOversightPage() {
  const organization = useCurrentOrganization();
  const { summary, recentRuns, isLoading, error } = usePatrolSummary(organization?.id);

  if (!organization) return <NoActiveOrganizationNotice resource="patrols" />;

  return (
    <PageContainer>
      <PageHeader title="Patrol Oversight" description="Guard tour activity across your organization over the last 7 days." />
      <ErrorAlert message={error} />

      {isLoading ? (
        <LoadingBlock label="Loading patrol oversight data…" />
      ) : (
        <>
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
            <StatCard label="Active patrols" value={summary?.activePatrols ?? 0} />
            <StatCard label="Completed" value={summary?.completedPatrols ?? 0} />
            <StatCard label="Incomplete" value={summary?.incompletePatrols ?? 0} tone={summary?.incompletePatrols ? 'warning' : undefined} />
            <StatCard label="Missed checkpoints" value={summary?.missedCheckpoints ?? 0} tone={summary?.missedCheckpoints ? 'danger' : undefined} />
            <StatCard label="Late checkpoints" value={summary?.lateCheckpoints ?? 0} tone={summary?.lateCheckpoints ? 'warning' : undefined} />
            <StatCard label="Exception rate" value={summary?.exceptionRate ?? 0} tone={summary && summary.exceptionRate > 10 ? 'warning' : undefined} />
          </div>

          <div className="mt-6 rounded-xl border border-border bg-surface-raised">
            <div className="border-b border-border px-4 py-3">
              <p className="text-sm font-medium text-content-primary">Recent patrol runs</p>
            </div>
            {recentRuns.length === 0 ? (
              <p className="px-4 py-6 text-sm text-content-secondary">No patrol runs recorded yet.</p>
            ) : (
              <ul className="divide-y divide-border">
                {recentRuns.map((run) => (
                  <li key={run.id} className="flex items-center justify-between px-4 py-3 text-sm">
                    <div>
                      <p className="font-medium text-content-primary">{new Date(run.startedAt).toLocaleString()}</p>
                      <p className="text-xs text-content-tertiary">
                        {run.scannedCheckpointCount} / {run.expectedCheckpointCount} checkpoints
                      </p>
                    </div>
                    <StatusBadge label={RUN_STATUS_LABEL[run.status]} tone={RUN_STATUS_TONE[run.status]} />
                  </li>
                ))}
              </ul>
            )}
          </div>
        </>
      )}
    </PageContainer>
  );
}
