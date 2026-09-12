import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import type { AttendanceCorrection } from '@/features/attendance/types/attendance.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const FIELD_LABEL: Record<string, string> = {
  clock_in_at: 'Clock-in time',
  clock_out_at: 'Clock-out time',
  status: 'Status',
};

/** Attendance correction review queue — attendance.manage tier (mirrors
 * can_manage_operations, the same tier attendance_records writes require). */
export function AttendanceCorrectionsPage() {
  const organization = useCurrentOrganization();
  const [corrections, setCorrections] = useState<AttendanceCorrection[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [decidingId, setDecidingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      setCorrections(await attendanceService.getCorrections(organization.id, 'pending'));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load attendance corrections.'));
    } finally {
      setIsLoading(false);
    }
  }, [organization]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!organization) return <NoActiveOrganizationNotice resource="attendance corrections" />;

  const decide = async (id: string, approve: boolean) => {
    setDecidingId(id);
    setError(null);
    try {
      await attendanceService.decideCorrection(id, approve, notes[id]?.trim() || undefined);
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to record the decision.'));
    } finally {
      setDecidingId(null);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Attendance Corrections" description="Review requested changes to clock-in/out times and attendance status." />

      <ErrorAlert message={error} />

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : corrections.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No pending correction requests.</p>
      ) : (
        <div className="mt-4 flex flex-col gap-3">
          {corrections.map((correction) => (
            <div key={correction.id} className="rounded-xl border border-border bg-surface-raised p-4">
              <p className="text-sm font-medium text-content-primary">{FIELD_LABEL[correction.field] ?? correction.field}</p>
              <p className="mt-1 text-sm text-content-secondary">
                {correction.previousValue ?? '—'} → <span className="font-medium text-content-primary">{correction.newValue}</span>
              </p>
              <p className="mt-1 text-sm text-content-secondary">Reason: {correction.reason}</p>
              <div className="mt-3">
                <TextField
                  label="Review notes"
                  placeholder="Optional"
                  value={notes[correction.id] ?? ''}
                  onChange={(event) => setNotes((prev) => ({ ...prev, [correction.id]: event.target.value }))}
                />
              </div>
              <div className="mt-3 flex gap-2">
                <Button variant="secondary" onClick={() => void decide(correction.id, false)} isLoading={decidingId === correction.id}>
                  Reject
                </Button>
                <Button onClick={() => void decide(correction.id, true)} isLoading={decidingId === correction.id}>
                  Approve
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </PageContainer>
  );
}
