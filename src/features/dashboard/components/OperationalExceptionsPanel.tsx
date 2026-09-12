import { useEffect, useState } from 'react';
import { StatPanel, type StatPanelTone } from '@/features/dashboard/components/DashboardPrimitives';
import { reportsService, type OperationalMetrics } from '@/features/reports/services/reportsService';

export interface OperationalExceptionsPanelProps {
  tenantId: string;
}

const toneForCount = (count: number): StatPanelTone => (count > 0 ? 'warning' : 'neutral');
const toneForCritical = (count: number): StatPanelTone => (count > 0 ? 'danger' : 'neutral');

/**
 * The dashboard's operational command-centre row: real exceptions the
 * signed-in manager needs to act on today, not vanity totals. Every
 * number comes from get_operational_metrics() (Phase R) — a SECURITY
 * INVOKER RPC already scoped by the caller's own RLS, so this panel
 * never needs its own permission logic; it simply renders whatever that
 * call returns. Shown only to roles that hold reports.view (see
 * WorkspaceDashboard) — an employee's dashboard stays focused on their
 * own day instead of tenant-wide figures they have no reason to see.
 */
export function OperationalExceptionsPanel({ tenantId }: OperationalExceptionsPanelProps) {
  const [metrics, setMetrics] = useState<OperationalMetrics | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const now = new Date();
    const periodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
    const periodEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10);
    setIsLoading(true);
    reportsService
      .getOperationalMetrics(tenantId, periodStart, periodEnd)
      .then((result) => {
        if (!cancelled) setMetrics(result);
      })
      .catch(() => {
        // A dashboard widget failing to load shouldn't break the page —
        // it simply renders nothing rather than an error banner.
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [tenantId]);

  if (!isLoading && !metrics) return null;

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      <StatPanel
        label="Open incidents"
        value={metrics ? metrics.openIncidentCount : '—'}
        caption={metrics && metrics.criticalIncidentCount > 0 ? `${metrics.criticalIncidentCount} critical` : 'None critical'}
        to="/incidents"
        isLoading={isLoading}
        tone={metrics ? toneForCritical(metrics.criticalIncidentCount) : 'neutral'}
      />
      <StatPanel
        label="Overdue tasks"
        value={metrics ? metrics.overdueTaskCount : '—'}
        caption="Past their due date"
        to="/tasks/management"
        isLoading={isLoading}
        tone={metrics ? toneForCount(metrics.overdueTaskCount) : 'neutral'}
      />
      <StatPanel
        label="Pending leave"
        value={metrics ? metrics.pendingLeaveRequests : '—'}
        caption="Awaiting a decision"
        to="/leave/management"
        isLoading={isLoading}
        tone={metrics ? toneForCount(metrics.pendingLeaveRequests) : 'neutral'}
      />
      <StatPanel
        label="Contracts expiring"
        value={metrics ? metrics.contractsExpiringCount : '—'}
        caption="Within 30 days"
        to="/contracts"
        isLoading={isLoading}
        tone={metrics ? toneForCount(metrics.contractsExpiringCount) : 'neutral'}
      />
      <StatPanel
        label="Certifications expiring"
        value={metrics ? metrics.qualificationsExpiringCount : '—'}
        caption="Within 30 days"
        to="/development/manage"
        isLoading={isLoading}
        tone={metrics ? toneForCount(metrics.qualificationsExpiringCount) : 'neutral'}
      />
    </div>
  );
}
