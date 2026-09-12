import { useMemo, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useMyAttendance } from '@/features/attendance/hooks/useMyAttendance';
import { useShifts } from '@/features/scheduling/hooks/useShifts';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { retryOnNetworkError } from '@/lib/retry';

function formatMinutes(minutes: number | null): string {
  if (minutes === null) return '—';
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return hours > 0 ? `${hours}h ${mins}m` : `${mins}m`;
}

const STATUS_LABEL: Record<string, string> = {
  present: 'Present',
  late: 'Late',
  absent: 'Absent',
  excused: 'Excused',
  unconfirmed: 'Unconfirmed',
};

/** Employee self-service: clock in/out, breaks, today's shift/status. Own
 * data only — RLS + the RPCs' own-employee checks are the real boundary,
 * this page just presents it. */
export function MyAttendancePage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();
  const { openRecord, openBreak, isLoading: attendanceLoading, error: attendanceError, refetch } = useMyAttendance(employee?.id);

  const todayRange = useMemo(() => {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const end = new Date();
    end.setHours(23, 59, 59, 999);
    return { rangeStart: start.toISOString(), rangeEnd: end.toISOString() };
  }, []);
  const { shifts } = useShifts(employee?.tenantId, { employeeId: employee?.id, ...todayRange });
  const todaysShift = shifts.find((s) => s.status !== 'cancelled');

  const [actionError, setActionError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [correctionReason, setCorrectionReason] = useState('');
  const [showCorrectionForm, setShowCorrectionForm] = useState(false);

  const isLoading = employeeLoading || attendanceLoading;

  const handleClockIn = async () => {
    if (!employee) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      await retryOnNetworkError(() => attendanceService.clockIn(employee.id, todaysShift?.siteId ?? employee.homeSiteId ?? '', todaysShift?.id));
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to clock in.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleClockOut = async () => {
    if (!openRecord) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      await retryOnNetworkError(() => attendanceService.clockOut(openRecord.id));
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to clock out.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleBreak = async () => {
    if (!openRecord) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      if (openBreak) {
        await attendanceService.endBreak(openRecord.id);
      } else {
        await attendanceService.startBreak(openRecord.id);
      }
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to update your break.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRequestCorrection = async () => {
    if (!openRecord || !correctionReason.trim()) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      await attendanceService.requestCorrection(openRecord.id, 'clock_in_at', new Date().toISOString(), correctionReason.trim());
      setCorrectionReason('');
      setShowCorrectionForm(false);
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to submit the correction request.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <PageContainer width="sm">
      <PageHeader title="My Attendance" description="Clock in, take breaks, and clock out for your shift." />

      <OfflineBanner />
      <ErrorAlert message={employeeError ?? attendanceError ?? actionError} />

      {isLoading ? (
        <LoadingBlock label="Loading your attendance status…" />
      ) : !employee ? (
        <p className="mt-6 text-sm text-content-secondary">No employee record is linked to your account.</p>
      ) : (
        <div className="mt-6 flex flex-col gap-4">
          <div className="rounded-xl border border-border bg-surface-raised p-5 text-center">
            {!openRecord ? (
              <>
                <p className="text-sm text-content-secondary">You are not clocked in.</p>
                {todaysShift && (
                  <p className="mt-1 text-xs text-content-tertiary">
                    Today's shift: {new Date(todaysShift.startsAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} –{' '}
                    {new Date(todaysShift.endsAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                  </p>
                )}
                <Button className="mt-4 w-full" onClick={() => void handleClockIn()} isLoading={isSubmitting}>
                  Clock in
                </Button>
              </>
            ) : (
              <>
                <span className="inline-flex items-center rounded-full bg-success-50 px-3 py-1 text-sm font-medium text-success-700 dark:bg-success-500/15 dark:text-success-200">
                  {STATUS_LABEL[openRecord.status] ?? openRecord.status}
                </span>
                <p className="mt-3 text-2xl font-bold text-content-primary">
                  Clocked in at {new Date(openRecord.clockInAt ?? '').toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </p>
                {openRecord.lateMinutes && <p className="mt-1 text-xs text-warning-600">{openRecord.lateMinutes} minute(s) late</p>}
                {openBreak && <p className="mt-1 text-xs text-content-tertiary">On break since {new Date(openBreak.breakStart).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>}

                <div className="mt-4 flex flex-col gap-2">
                  <Button variant="secondary" onClick={() => void handleBreak()} isLoading={isSubmitting}>
                    {openBreak ? 'End break' : 'Start break'}
                  </Button>
                  <Button onClick={() => void handleClockOut()} isLoading={isSubmitting} disabled={Boolean(openBreak)}>
                    Clock out
                  </Button>
                  {openBreak && <p className="text-xs text-content-tertiary">End your break before clocking out.</p>}
                </div>
              </>
            )}
          </div>

          {openRecord?.clockOutAt && (
            <div className="rounded-xl border border-border bg-surface-raised p-4 text-sm">
              <p className="font-medium text-content-primary">Today's summary</p>
              <dl className="mt-2 grid grid-cols-2 gap-2 text-content-secondary">
                <dt>Worked</dt>
                <dd>{formatMinutes(openRecord.workedMinutes)}</dd>
                {openRecord.overtimeMinutes && (
                  <>
                    <dt>Overtime</dt>
                    <dd>{formatMinutes(openRecord.overtimeMinutes)}</dd>
                  </>
                )}
              </dl>
            </div>
          )}

          {openRecord && (
            <div className="rounded-xl border border-border bg-surface-raised p-4">
              {!showCorrectionForm ? (
                <Button variant="ghost" onClick={() => setShowCorrectionForm(true)}>
                  Request a correction
                </Button>
              ) : (
                <div className="flex flex-col gap-2">
                  <TextField
                    label="Reason for correction"
                    placeholder="e.g. forgot to clock in on time"
                    value={correctionReason}
                    onChange={(event) => setCorrectionReason(event.target.value)}
                  />
                  <div className="flex gap-2">
                    <Button onClick={() => void handleRequestCorrection()} isLoading={isSubmitting} disabled={!correctionReason.trim()}>
                      Submit request
                    </Button>
                    <Button variant="ghost" onClick={() => setShowCorrectionForm(false)}>
                      Cancel
                    </Button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </PageContainer>
  );
}
