import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAuth } from '@/features/auth/context/authContext';
import { hasPermission } from '@/features/rbac';
import { reportsService, type OperationalMetrics } from '@/features/reports/services/reportsService';
import { toCsv } from '@/lib/csv';
import { getDbErrorMessage } from '@/lib/dbErrors';

interface MetricCard {
  label: string;
  value: string;
  hint?: string;
}

function buildCards(m: OperationalMetrics): MetricCard[] {
  return [
    { label: 'Active employees', value: String(m.activeEmployeeCount) },
    { label: 'Attendance rate', value: `${m.attendanceRatePct.toFixed(1)}%`, hint: `${m.lateAttendanceCount} late records` },
    { label: 'Pending leave requests', value: String(m.pendingLeaveRequests) },
    { label: 'Approved leave days (period)', value: String(m.approvedLeaveDays) },
    { label: 'Task completion rate', value: `${m.taskCompletionRatePct.toFixed(1)}%`, hint: `${m.overdueTaskCount} overdue` },
    { label: 'Open incidents', value: String(m.openIncidentCount), hint: `${m.criticalIncidentCount} critical` },
    { label: 'Active assets', value: String(m.activeAssetCount), hint: `${m.assetsInMaintenanceCount} in maintenance` },
    { label: 'Active contracts', value: String(m.activeContractCount), hint: `${m.contractsExpiringCount} expiring within 30 days` },
    { label: 'Certifications expiring soon', value: String(m.qualificationsExpiringCount) },
    { label: 'Trainings completed (period)', value: String(m.trainingsCompletedCount) },
  ];
}

/** Every figure here comes straight from get_operational_metrics() — a
 * SECURITY INVOKER RPC (see its migration comment) whose aggregates are
 * already scoped by the signed-in caller's own RLS, so a site_manager and
 * an organization_administrator calling this same page each see only what
 * their existing table-level permissions already allow (R.3) — no
 * additional role filtering is implemented in this component. */
export function ReportsPage() {
  const organization = useCurrentOrganization();
  const { user } = useAuth();
  const canExport = hasPermission(user?.role ?? null, 'reports.export');
  const [metrics, setMetrics] = useState<OperationalMetrics | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const now = new Date();
  const periodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
  const periodEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10);

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      setMetrics(await reportsService.getOperationalMetrics(organization.id, periodStart, periodEnd));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load operational metrics.'));
    } finally {
      setIsLoading(false);
    }
  }, [organization, periodStart, periodEnd]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!organization) return <NoActiveOrganizationNotice resource="reports" />;

  const handleExport = () => {
    if (!metrics) return;
    const csv = toCsv(buildCards(metrics), [
      { key: 'label', header: 'Metric' },
      { key: 'value', header: 'Value' },
      { key: 'hint', header: 'Detail' },
    ]);
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `sebetsa-operational-metrics-${periodStart}-to-${periodEnd}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <PageContainer>
      <PageHeader
        title="Reports"
        description={`Operational metrics for ${periodStart} to ${periodEnd}, derived from your own live data.`}
        action={
          canExport && metrics ? (
            <Button variant="secondary" onClick={handleExport}>
              Export CSV
            </Button>
          ) : undefined
        }
      />

      <ErrorAlert message={error} />

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : !metrics ? (
        <p className="mt-6 text-sm text-content-secondary">No metrics available.</p>
      ) : (
        <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {buildCards(metrics).map((card) => (
            <div key={card.label} className="rounded-xl border border-border bg-surface-raised p-4">
              <p className="text-xs font-medium uppercase tracking-wide text-content-tertiary">{card.label}</p>
              <p className="mt-1 text-2xl font-semibold text-content-primary">{card.value}</p>
              {card.hint && <p className="mt-1 text-xs text-content-tertiary">{card.hint}</p>}
            </div>
          ))}
        </div>
      )}
    </PageContainer>
  );
}
