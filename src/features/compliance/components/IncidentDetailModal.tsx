import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { incidentService } from '@/features/compliance/services/incidentService';
import { INCIDENT_STATUS_LABELS } from '@/features/compliance/types/compliance.types';
import type { Incident, IncidentAction } from '@/features/compliance/types/compliance.types';
import type { IncidentStatusEnum } from '@/lib/dbTypes';
import { getDbErrorMessage } from '@/lib/dbErrors';

const NEXT_STATUS: Partial<Record<IncidentStatusEnum, IncidentStatusEnum>> = {
  reported: 'acknowledged',
  acknowledged: 'investigating',
  investigating: 'corrective_action',
  corrective_action: 'pending_closure',
  pending_closure: 'closed',
};

export interface IncidentDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  incident: Incident | null;
  canManage: boolean;
  onChanged: () => void;
}

export function IncidentDetailModal({ isOpen, onClose, incident, canManage, onChanged }: IncidentDetailModalProps) {
  const [actions, setActions] = useState<IncidentAction[]>([]);
  const [newActionDescription, setNewActionDescription] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!isOpen || !incident) return;
    setError(null);
    void incidentService.getIncidentActions(incident.id).then(setActions);
  }, [isOpen, incident]);

  if (!incident) return null;

  const refreshActions = () => void incidentService.getIncidentActions(incident.id).then(setActions);

  const handleAdvance = async () => {
    const next = NEXT_STATUS[incident.status];
    if (!next) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await incidentService.transitionIncidentStatus(incident.id, next);
      onChanged();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to update the incident status.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleReopen = async () => {
    setIsSubmitting(true);
    setError(null);
    try {
      await incidentService.transitionIncidentStatus(incident.id, 'investigating', 'Reopened for further investigation');
      onChanged();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to reopen the incident.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleAddAction = async () => {
    if (!newActionDescription.trim()) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await incidentService.addIncidentAction(incident.id, newActionDescription.trim());
      setNewActionDescription('');
      refreshActions();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to add the corrective action.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleCompleteAction = async (actionId: string) => {
    setError(null);
    try {
      await incidentService.completeIncidentAction(actionId);
      refreshActions();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to complete the action.'));
    }
  };

  const handleVerifyAction = async (actionId: string) => {
    setError(null);
    try {
      await incidentService.verifyIncidentAction(actionId);
      refreshActions();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to verify the action.'));
    }
  };

  const nextStatus = NEXT_STATUS[incident.status];

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Incident ${incident.referenceNumber}`}>
      <div className="flex flex-col gap-4">
        {error && <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">{error}</div>}

        <p className="text-sm text-content-secondary">{incident.description}</p>
        <p className="text-xs text-content-tertiary">Status: {INCIDENT_STATUS_LABELS[incident.status]}</p>

        {canManage && (
          <div className="flex flex-wrap gap-2">
            {nextStatus && (
              <Button onClick={() => void handleAdvance()} isLoading={isSubmitting}>
                Move to {INCIDENT_STATUS_LABELS[nextStatus]}
              </Button>
            )}
            {(incident.status === 'closed' || incident.status === 'pending_closure') && (
              <Button variant="secondary" onClick={() => void handleReopen()} isLoading={isSubmitting}>
                Reopen for investigation
              </Button>
            )}
          </div>
        )}

        <div>
          <p className="text-sm font-medium text-content-primary">Corrective / preventive actions</p>
          <div className="mt-2 flex flex-col gap-2">
            {actions.length === 0 && <p className="text-xs text-content-tertiary">No actions recorded yet.</p>}
            {actions.map((action) => (
              <div key={action.id} className="flex items-center justify-between rounded-lg border border-border bg-surface-sunken px-3 py-2 text-sm">
                <div>
                  <p className="text-content-primary">{action.description}</p>
                  <p className="text-xs text-content-tertiary">{action.status}{action.dueDate ? ` — due ${new Date(action.dueDate).toLocaleDateString()}` : ''}</p>
                </div>
                <div className="flex gap-2">
                  {action.status !== 'completed' && action.status !== 'verified' && (
                    <Button variant="ghost" onClick={() => void handleCompleteAction(action.id)}>Complete</Button>
                  )}
                  {canManage && action.status === 'completed' && (
                    <Button variant="ghost" onClick={() => void handleVerifyAction(action.id)}>Verify</Button>
                  )}
                </div>
              </div>
            ))}
          </div>
          {canManage && (
            <div className="mt-2 flex gap-2">
              <TextField label="New action" placeholder="Describe the corrective action" value={newActionDescription} onChange={(event) => setNewActionDescription(event.target.value)} />
              <Button variant="secondary" onClick={() => void handleAddAction()} isLoading={isSubmitting} disabled={!newActionDescription.trim()}>
                Add
              </Button>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
