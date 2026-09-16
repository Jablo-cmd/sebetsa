import { useMemo, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useShifts } from '@/features/scheduling/hooks/useShifts';
import { useMyActivePatrol } from '@/features/patrols/hooks/useMyActivePatrol';
import { useAssignedPatrolRoutes } from '@/features/patrols/hooks/useAssignedPatrolRoutes';
import { CheckpointScanner } from '@/features/patrols/components/CheckpointScanner';
import { patrolService } from '@/features/patrols/services/patrolService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { useDeviceLocation } from '@/lib/useDeviceLocation';
import type { CheckpointScanType, CheckpointScanResult } from '@/features/patrols/types/patrol.types';
import type { StatusTone } from '@/components/ui/StatusBadge';

const SCAN_RESULT_LABEL: Record<CheckpointScanResult, string> = {
  valid: 'Scanned',
  wrong_sequence: 'Wrong order',
  duplicate: 'Already scanned',
  out_of_window: 'Too late',
  invalid_checkpoint: 'Unknown checkpoint',
  not_assigned: 'Not assigned',
};

const SCAN_RESULT_TONE: Record<CheckpointScanResult, StatusTone> = {
  valid: 'success',
  wrong_sequence: 'warning',
  duplicate: 'warning',
  out_of_window: 'warning',
  invalid_checkpoint: 'danger',
  not_assigned: 'danger',
};

/** Employee-facing guard tour: start a patrol, scan checkpoints, complete it — own data only, RLS + start_patrol()'s own site-assignment check are the real boundary. */
export function MyPatrolsPage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();

  const todayRange = useMemo(() => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const end = new Date();
    end.setHours(23, 59, 59, 999);
    return { rangeStart: start.toISOString(), rangeEnd: end.toISOString() };
  }, []);
  const { shifts } = useShifts(employee?.tenantId, { employeeId: employee?.id, ...todayRange });
  const todaysSiteId = shifts.find((s) => s.status !== 'cancelled')?.siteId ?? employee?.homeSiteId ?? null;

  const { routes, isLoading: routesLoading, error: routesError } = useAssignedPatrolRoutes(todaysSiteId);
  const { activeRun, scans, isLoading: patrolLoading, error: patrolError, refetch } = useMyActivePatrol(employee?.id);
  const { read: readLocation } = useDeviceLocation();

  const [selectedRouteId, setSelectedRouteId] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const isLoading = employeeLoading || routesLoading || patrolLoading;

  const handleStart = async () => {
    if (!selectedRouteId) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      await patrolService.startPatrol(selectedRouteId);
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to start the patrol.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleScan = async (code: string, method: CheckpointScanType) => {
    if (!activeRun) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      const location = await readLocation();
      await patrolService.scanCheckpoint(activeRun.id, code, location, method);
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to record the checkpoint scan.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleComplete = async () => {
    if (!activeRun) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      await patrolService.completePatrol(activeRun.id);
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to complete the patrol.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <PageContainer width="sm">
      <PageHeader title="My Patrols" description="Start a patrol, scan each checkpoint in order, then complete it." />

      <OfflineBanner />
      <ErrorAlert message={employeeError ?? routesError ?? patrolError ?? actionError} />

      {isLoading ? (
        <LoadingBlock label="Loading your patrol status…" />
      ) : !employee ? (
        <p className="mt-6 text-sm text-content-secondary">No employee record is linked to your account.</p>
      ) : activeRun ? (
        <div className="flex flex-col gap-4">
          <div className="rounded-xl border border-border bg-surface-raised p-5">
            <p className="text-sm text-content-secondary">Patrol in progress</p>
            <p className="mt-1 text-2xl font-bold text-content-primary">
              {activeRun.scannedCheckpointCount} / {activeRun.expectedCheckpointCount} checkpoints
            </p>
            <p className="mt-1 text-xs text-content-tertiary">Started {new Date(activeRun.startedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
          </div>

          <div className="rounded-xl border border-border bg-surface-raised p-4">
            <p className="mb-3 text-sm font-medium text-content-primary">Scan a checkpoint</p>
            <CheckpointScanner onScan={handleScan} isSubmitting={isSubmitting} />
          </div>

          {scans.length > 0 && (
            <div className="rounded-xl border border-border bg-surface-raised p-4">
              <p className="mb-2 text-sm font-medium text-content-primary">Scan history</p>
              <ul className="flex flex-col gap-2">
                {scans.map((scan) => (
                  <li key={scan.id} className="flex items-center justify-between text-sm">
                    <span className="text-content-secondary">
                      {scan.scannedCode ?? 'checkpoint'} · {new Date(scan.scannedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </span>
                    <StatusBadge label={SCAN_RESULT_LABEL[scan.verificationResult]} tone={SCAN_RESULT_TONE[scan.verificationResult]} />
                  </li>
                ))}
              </ul>
            </div>
          )}

          <Button onClick={() => void handleComplete()} isLoading={isSubmitting}>
            Complete patrol
          </Button>
        </div>
      ) : (
        <div className="rounded-xl border border-border bg-surface-raised p-5">
          {routes.length === 0 ? (
            <p className="text-sm text-content-secondary">No patrol route is configured for your site yet.</p>
          ) : (
            <>
              <label htmlFor="patrol-route" className="mb-1.5 block text-sm font-medium text-content-primary">
                Choose a route
              </label>
              <select
                id="patrol-route"
                value={selectedRouteId}
                onChange={(event) => setSelectedRouteId(event.target.value)}
                className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              >
                <option value="">Select a route…</option>
                {routes.map((route) => (
                  <option key={route.id} value={route.id}>
                    {route.name}
                  </option>
                ))}
              </select>
              <Button className="mt-4 w-full" onClick={() => void handleStart()} isLoading={isSubmitting} disabled={!selectedRouteId}>
                Start patrol
              </Button>
            </>
          )}
        </div>
      )}
    </PageContainer>
  );
}
