import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { leaveService } from '@/features/leave/services/leaveService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { LeaveRequest, LeaveType, AffectedShift } from '@/features/leave/types/leave.types';

export interface LeaveApprovalDialogProps {
  isOpen: boolean;
  onClose: () => void;
  request: LeaveRequest | null;
  leaveTypes: LeaveType[];
  onDecided: (request: LeaveRequest) => void;
}

/** Approve/reject a pending request, or revoke an already-approved one — one
 * dialog covers both since only one action is ever available per status. */
export function LeaveApprovalDialog({ isOpen, onClose, request, leaveTypes, onDecided }: LeaveApprovalDialogProps) {
  const [notes, setNotes] = useState('');
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [affectedShifts, setAffectedShifts] = useState<AffectedShift[]>([]);

  useEffect(() => {
    if (!isOpen || !request) return;
    setNotes('');
    setSubmitError(null);
    void leaveService.getAffectedShifts(request.id).then(setAffectedShifts).catch(() => setAffectedShifts([]));
  }, [isOpen, request]);

  if (!request) return null;

  const leaveTypeName = leaveTypes.find((t) => t.id === request.leaveTypeId)?.name ?? '—';

  const decide = async (action: 'approve' | 'reject' | 'revoke') => {
    setIsSubmitting(true);
    setSubmitError(null);
    try {
      const decided =
        action === 'approve'
          ? await leaveService.approveLeaveRequest(request.id, notes.trim() || undefined)
          : action === 'reject'
            ? await leaveService.rejectLeaveRequest(request.id, notes.trim() || undefined)
            : await leaveService.revokeLeaveRequest(request.id, notes.trim() || undefined);
      onDecided(decided);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to record the decision.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Review leave request">
      <div className="flex flex-col gap-4">
        {submitError && (
          <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">
            {submitError}
          </div>
        )}

        <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
          <dt className="text-content-secondary">Leave type</dt>
          <dd className="text-content-primary">{leaveTypeName}</dd>
          <dt className="text-content-secondary">Dates</dt>
          <dd className="text-content-primary">
            {request.startDate === request.endDate ? request.startDate : `${request.startDate} – ${request.endDate}`}
            {request.isHalfDay && ` (half day, ${request.halfDayPeriod?.toUpperCase()})`}
          </dd>
          {request.reason && (
            <>
              <dt className="text-content-secondary">Reason</dt>
              <dd className="text-content-primary">{request.reason}</dd>
            </>
          )}
        </dl>

        {affectedShifts.length > 0 && (
          <div className="rounded-lg border border-warning-500/30 bg-warning-50 px-3.5 py-2.5 text-sm text-warning-700 dark:bg-warning-500/15 dark:text-warning-200">
            <p className="font-medium">{affectedShifts.length} scheduled shift(s) overlap this leave range.</p>
            <p className="mt-1 text-xs">Review Schedule to reassign or record a substitution — approving here does not change any shift.</p>
          </div>
        )}

        <TextField label="Notes" placeholder="Optional" value={notes} onChange={(event) => setNotes(event.target.value)} />

        <div className="flex flex-wrap justify-end gap-2">
          {request.status === 'pending' && (
            <>
              <Button variant="secondary" onClick={() => void decide('reject')} isLoading={isSubmitting}>
                Reject
              </Button>
              <Button onClick={() => void decide('approve')} isLoading={isSubmitting}>
                Approve
              </Button>
            </>
          )}
          {request.status === 'approved' && (
            <Button variant="secondary" onClick={() => void decide('revoke')} isLoading={isSubmitting}>
              Revoke
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
}
