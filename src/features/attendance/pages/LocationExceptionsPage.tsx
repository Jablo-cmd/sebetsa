import { useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { AttendanceLocationException } from '@/features/attendance/types/attendance.types';

/**
 * The supervisor-reviewed side of the GPS exception workflow (employee-side
 * request lives in MyAttendancePage). The original GPS evidence
 * (attendance_location_events) is never edited by this decision — see
 * decide_attendance_location_exception()'s own comments; approving an
 * exception only records a human judgement layered on top of it.
 */
export function LocationExceptionsPage() {
  const organization = useCurrentOrganization();
  const [exceptions, setExceptions] = useState<AttendanceLocationException[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [decidingId, setDecidingId] = useState<string | null>(null);
  const [reviewNotes, setReviewNotes] = useState('');

  useEffect(() => {
    if (!organization) return;
    attendanceService
      .getPendingLocationExceptions(organization.id)
      .then(setExceptions)
      .catch((err) => setError(getDbErrorMessage(err, 'Failed to load pending GPS exceptions.')))
      .finally(() => setIsLoading(false));
  }, [organization]);

  if (!organization) return <NoActiveOrganizationNotice resource="GPS exception review" />;

  const handleDecide = async (exceptionId: string, approve: boolean) => {
    setBusyId(exceptionId);
    setError(null);
    try {
      await attendanceService.decideLocationException(exceptionId, approve, reviewNotes.trim() || undefined);
      setExceptions((prev) => prev.filter((e) => e.id !== exceptionId));
      setDecidingId(null);
      setReviewNotes('');
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to record your decision.'));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Location Exceptions" description="Employee requests for a clock-in that failed GPS verification. The original location evidence is never altered by this decision." />
      <ErrorAlert message={error} />

      {isLoading ? (
        <LoadingBlock label="Loading pending GPS exceptions…" />
      ) : exceptions.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No pending GPS exception requests.</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {exceptions.map((exception) => (
            <li key={exception.id} className="rounded-xl border border-border bg-surface-raised p-4">
              <p className="text-sm text-content-primary">{exception.reason}</p>
              <p className="mt-1 text-xs text-content-tertiary">Requested {new Date(exception.createdAt).toLocaleString()}</p>

              {decidingId === exception.id ? (
                <div className="mt-3 flex flex-col gap-2 border-t border-border pt-3">
                  <TextField label="Review notes (optional)" value={reviewNotes} onChange={(event) => setReviewNotes(event.target.value)} />
                  <div className="flex gap-2">
                    <Button className="h-9" onClick={() => void handleDecide(exception.id, true)} isLoading={busyId === exception.id}>
                      Approve
                    </Button>
                    <Button variant="secondary" className="h-9" onClick={() => void handleDecide(exception.id, false)} isLoading={busyId === exception.id}>
                      Reject
                    </Button>
                    <Button variant="ghost" className="h-9" onClick={() => setDecidingId(null)}>
                      Cancel
                    </Button>
                  </div>
                </div>
              ) : (
                <Button
                  variant="secondary"
                  className="mt-3 h-9"
                  onClick={() => {
                    setDecidingId(exception.id);
                    setReviewNotes('');
                  }}
                >
                  Review
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
    </PageContainer>
  );
}
