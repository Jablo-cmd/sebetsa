import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useActiveEmergencies } from '@/features/emergency/hooks/useActiveEmergencies';
import { emergencyService } from '@/features/emergency/services/emergencyService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { EmergencyStatus } from '@/features/emergency/types/emergency.types';
import type { StatusTone } from '@/components/ui/StatusBadge';

const STATUS_LABEL: Record<EmergencyStatus, string> = {
  triggered: 'Triggered — unacknowledged',
  acknowledged: 'Acknowledged',
  responding: 'Responding',
  resolved: 'Resolved',
};

const STATUS_TONE: Record<EmergencyStatus, StatusTone> = {
  triggered: 'danger',
  acknowledged: 'warning',
  responding: 'info',
  resolved: 'success',
};

/**
 * Safety-critical lifecycle (triggered -> acknowledged -> responding ->
 * resolved), never a boolean flag. Location + identity is the most
 * sensitive data this domain touches — this page is only reachable by the
 * operations-management tier (emergency.view), matching the RLS on
 * emergency_events/emergency_responses exactly.
 */
export function EmergencyResponsePage() {
  const organization = useCurrentOrganization();
  const { emergencies, isLoading, error, refetch } = useActiveEmergencies(organization?.id);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busyEventId, setBusyEventId] = useState<string | null>(null);
  const [resolvingEventId, setResolvingEventId] = useState<string | null>(null);
  const [resolutionReason, setResolutionReason] = useState('');

  if (!organization) return <NoActiveOrganizationNotice resource="emergency response" />;

  const handleAcknowledge = async (eventId: string) => {
    setBusyEventId(eventId);
    setActionError(null);
    try {
      await emergencyService.acknowledgeEmergency(eventId);
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to acknowledge the emergency.'));
    } finally {
      setBusyEventId(null);
    }
  };

  const handleRespond = async (eventId: string) => {
    setBusyEventId(eventId);
    setActionError(null);
    try {
      await emergencyService.respondToEmergency(eventId);
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to mark the emergency as responding.'));
    } finally {
      setBusyEventId(null);
    }
  };

  const handleResolve = async (eventId: string) => {
    if (!resolutionReason.trim()) return;
    setBusyEventId(eventId);
    setActionError(null);
    try {
      await emergencyService.resolveEmergency(eventId, resolutionReason.trim());
      setResolvingEventId(null);
      setResolutionReason('');
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to resolve the emergency.'));
    } finally {
      setBusyEventId(null);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Emergency Response" description="Active panic, medical, and security alerts requiring a response." />
      <ErrorAlert message={error ?? actionError} />

      {isLoading ? (
        <LoadingBlock label="Loading active emergencies…" />
      ) : emergencies.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No active emergencies. Everything is clear.</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {emergencies.map(({ event, response }) => (
            <li key={event.id} className="rounded-xl border border-danger-500/30 bg-surface-raised p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <div className="flex items-center gap-2">
                    <StatusBadge label={event.emergencyType.replace('_', ' ')} tone="danger" />
                    <StatusBadge label={STATUS_LABEL[response.status]} tone={STATUS_TONE[response.status]} />
                  </div>
                  <p className="mt-1 text-xs text-content-tertiary">
                    Triggered {new Date(event.triggeredAt).toLocaleString()}
                    {response.escalationLevel > 0 ? ` · escalated to level ${response.escalationLevel}` : ''}
                  </p>
                  {event.latitude !== null && event.longitude !== null && (
                    <p className="mt-1 text-xs text-content-tertiary">
                      Location: {event.latitude.toFixed(5)}, {event.longitude.toFixed(5)}
                    </p>
                  )}
                </div>

                <div className="flex gap-2">
                  {response.status === 'triggered' && (
                    <Button className="h-9" onClick={() => void handleAcknowledge(event.id)} isLoading={busyEventId === event.id}>
                      Acknowledge
                    </Button>
                  )}
                  {response.status === 'acknowledged' && (
                    <Button className="h-9" onClick={() => void handleRespond(event.id)} isLoading={busyEventId === event.id}>
                      Mark responding
                    </Button>
                  )}
                  {(response.status === 'acknowledged' || response.status === 'responding') && resolvingEventId !== event.id && (
                    <Button variant="secondary" className="h-9" onClick={() => setResolvingEventId(event.id)}>
                      Resolve
                    </Button>
                  )}
                </div>
              </div>

              {resolvingEventId === event.id && (
                <div className="mt-3 flex flex-col gap-2 border-t border-border pt-3">
                  <TextField
                    label="Resolution notes"
                    placeholder="e.g. false alarm, guard confirmed safe"
                    value={resolutionReason}
                    onChange={(event_) => setResolutionReason(event_.target.value)}
                  />
                  <div className="flex gap-2">
                    <Button className="h-9" onClick={() => void handleResolve(event.id)} isLoading={busyEventId === event.id} disabled={!resolutionReason.trim()}>
                      Confirm resolution
                    </Button>
                    <Button variant="ghost" className="h-9" onClick={() => setResolvingEventId(null)}>
                      Cancel
                    </Button>
                  </div>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </PageContainer>
  );
}
