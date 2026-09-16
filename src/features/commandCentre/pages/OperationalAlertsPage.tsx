import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { Button } from '@/components/ui/Button';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useOperationalAlerts } from '@/features/commandCentre/hooks/useOperationalAlerts';
import { commandCentreService } from '@/features/commandCentre/services/commandCentreService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { AlertSeverity, AlertStatus } from '@/features/commandCentre/types/commandCentre.types';
import type { StatusTone } from '@/components/ui/StatusBadge';

const SEVERITY_TONE: Record<AlertSeverity, StatusTone> = { info: 'info', warning: 'warning', critical: 'danger' };
const STATUS_TONE: Record<AlertStatus, StatusTone> = { open: 'warning', acknowledged: 'info', resolved: 'success' };

const FILTERS: { value: AlertStatus | undefined; label: string }[] = [
  { value: undefined, label: 'All' },
  { value: 'open', label: 'Open' },
  { value: 'acknowledged', label: 'Acknowledged' },
  { value: 'resolved', label: 'Resolved' },
];

/** Deterministic system-raised alerts (open -> acknowledged -> resolved), never a direct client insert — see raise_*_alerts() sweep functions. */
export function OperationalAlertsPage() {
  const organization = useCurrentOrganization();
  const [statusFilter, setStatusFilter] = useState<AlertStatus | undefined>('open');
  const { alerts, isLoading, error, refetch } = useOperationalAlerts(organization?.id, statusFilter);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busyAlertId, setBusyAlertId] = useState<string | null>(null);

  if (!organization) return <NoActiveOrganizationNotice resource="operational alerts" />;

  const handleAcknowledge = async (alertId: string) => {
    setBusyAlertId(alertId);
    setActionError(null);
    try {
      await commandCentreService.acknowledgeAlert(alertId);
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to acknowledge the alert.'));
    } finally {
      setBusyAlertId(null);
    }
  };

  const handleResolve = async (alertId: string) => {
    setBusyAlertId(alertId);
    setActionError(null);
    try {
      await commandCentreService.resolveAlert(alertId);
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to resolve the alert.'));
    } finally {
      setBusyAlertId(null);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Operational Alerts" description="System-raised alerts for understaffing, missed patrols, SLA breaches, and more." />
      <ErrorAlert message={error ?? actionError} />

      <div className="flex gap-2">
        {FILTERS.map((filter) => (
          <button
            key={filter.label}
            type="button"
            onClick={() => setStatusFilter(filter.value)}
            data-active={statusFilter === filter.value}
            className="focus-ring rounded-full border border-border-strong px-3 py-1.5 text-xs font-medium text-content-secondary data-[active=true]:border-brand-500 data-[active=true]:bg-brand-50 data-[active=true]:text-brand-700 dark:data-[active=true]:bg-brand-500/15 dark:data-[active=true]:text-brand-200"
          >
            {filter.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <LoadingBlock label="Loading operational alerts…" />
      ) : alerts.length === 0 ? (
        <p className="mt-4 text-sm text-content-secondary">No alerts match this filter.</p>
      ) : (
        <ul className="mt-2 flex flex-col gap-2">
          {alerts.map((alert) => (
            <li key={alert.id} className="flex flex-col gap-2 rounded-xl border border-border bg-surface-raised p-4 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex flex-col gap-1">
                <div className="flex items-center gap-2">
                  <StatusBadge label={alert.severity} tone={SEVERITY_TONE[alert.severity]} />
                  <StatusBadge label={alert.status} tone={STATUS_TONE[alert.status]} />
                </div>
                <p className="text-sm text-content-primary">{alert.message}</p>
                <p className="text-xs text-content-tertiary">{new Date(alert.createdAt).toLocaleString()}</p>
              </div>
              {alert.status !== 'resolved' && (
                <div className="flex gap-2">
                  {alert.status === 'open' && (
                    <Button variant="secondary" className="h-9" onClick={() => void handleAcknowledge(alert.id)} isLoading={busyAlertId === alert.id}>
                      Acknowledge
                    </Button>
                  )}
                  <Button className="h-9" onClick={() => void handleResolve(alert.id)} isLoading={busyAlertId === alert.id}>
                    Resolve
                  </Button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </PageContainer>
  );
}
