import { useMemo, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useMyAttendance } from '@/features/attendance/hooks/useMyAttendance';
import { useMyLocationExceptions } from '@/features/attendance/hooks/useMyLocationExceptions';
import { useShifts } from '@/features/scheduling/hooks/useShifts';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { retryOnNetworkError } from '@/lib/retry';
import { useDeviceLocation } from '@/lib/useDeviceLocation';
import type { GpsVerificationStatus, AttendanceLocationExceptionStatus } from '@/features/attendance/types/attendance.types';
import type { StatusTone } from '@/components/ui/StatusBadge';

const EXCEPTION_STATUS_TONE: Record<AttendanceLocationExceptionStatus, StatusTone> = {
  pending: 'warning',
  approved: 'success',
  rejected: 'danger',
};

const GPS_STATUS_LABEL: Record<GpsVerificationStatus, string> = {
  verified: 'Location verified',
  outside_geofence: 'Outside site geofence',
  low_accuracy: 'GPS accuracy too low',
  location_unavailable: 'Location unavailable',
  pending_verification: 'No geofence configured',
  offline_pending: 'Captured offline — pending sync',
  manual_review: 'Flagged for review',
  not_applicable: 'Clocked in by a manager',
};

const GPS_STATUS_TONE: Record<GpsVerificationStatus, StatusTone> = {
  verified: 'success',
  outside_geofence: 'warning',
  low_accuracy: 'warning',
  location_unavailable: 'warning',
  pending_verification: 'neutral',
  offline_pending: 'info',
  manual_review: 'warning',
  not_applicable: 'neutral',
};

/** GPS states a supervisor-reviewed exception makes sense for — see attendance_location_exceptions' own invalid_request check. */
const EXCEPTION_ELIGIBLE_STATUSES: GpsVerificationStatus[] = ['outside_geofence', 'location_unavailable', 'low_accuracy'];

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
  const { exceptions: myExceptions, refetch: refetchExceptions } = useMyLocationExceptions(employee?.id);

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
  const [exceptionReason, setExceptionReason] = useState('');
  const [showExceptionForm, setShowExceptionForm] = useState(false);
  const [exceptionRequested, setExceptionRequested] = useState(false);
  const { isReading: isReadingLocation, read: readLocation } = useDeviceLocation();

  const isLoading = employeeLoading || attendanceLoading;

  const handleClockIn = async () => {
    if (!employee) return;
    setIsSubmitting(true);
    setActionError(null);
    setExceptionRequested(false);
    try {
      const location = await readLocation();
      await retryOnNetworkError(() =>
        attendanceService.clockIn(employee.id, todaysShift?.siteId ?? employee.homeSiteId ?? '', todaysShift?.id, location),
      );
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
      const location = await readLocation();
      await retryOnNetworkError(() => attendanceService.clockOut(openRecord.id, location));
      void refetch();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to clock out.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRequestLocationException = async () => {
    if (!openRecord || !exceptionReason.trim()) return;
    setIsSubmitting(true);
    setActionError(null);
    try {
      await attendanceService.requestLocationException(openRecord.id, exceptionReason.trim());
      setExceptionReason('');
      setShowExceptionForm(false);
      setExceptionRequested(true);
      void refetchExceptions();
    } catch (error) {
      setActionError(getDbErrorMessage(error, 'Failed to submit the location exception request.'));
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
                <Button className="mt-4 w-full" onClick={() => void handleClockIn()} isLoading={isSubmitting || isReadingLocation}>
                  Clock in
                </Button>
                <p className="mt-2 text-xs text-content-tertiary">We'll ask for your location to confirm you're on site.</p>
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

                <div className="mt-3">
                  <StatusBadge label={GPS_STATUS_LABEL[openRecord.gpsVerificationStatus]} tone={GPS_STATUS_TONE[openRecord.gpsVerificationStatus]} />
                </div>

                <div className="mt-4 flex flex-col gap-2">
                  <Button variant="secondary" onClick={() => void handleBreak()} isLoading={isSubmitting}>
                    {openBreak ? 'End break' : 'Start break'}
                  </Button>
                  <Button onClick={() => void handleClockOut()} isLoading={isSubmitting || isReadingLocation} disabled={Boolean(openBreak)}>
                    Clock out
                  </Button>
                  {openBreak && <p className="text-xs text-content-tertiary">End your break before clocking out.</p>}
                </div>

                {EXCEPTION_ELIGIBLE_STATUSES.includes(openRecord.gpsVerificationStatus) && (
                  <div className="mt-4 rounded-lg border border-warning-500/30 bg-warning-50 p-3 text-left dark:bg-warning-500/10">
                    {exceptionRequested ? (
                      <p className="text-xs font-medium text-warning-600">Your location exception request has been submitted for supervisor review.</p>
                    ) : !showExceptionForm ? (
                      <>
                        <p className="text-xs text-warning-600">
                          We couldn't confirm you were at the site. If this is wrong (e.g. your GPS was inaccurate), you can ask a supervisor to review it.
                        </p>
                        <Button variant="ghost" className="mt-2 h-9" onClick={() => setShowExceptionForm(true)}>
                          Request a location exception
                        </Button>
                      </>
                    ) : (
                      <div className="flex flex-col gap-2">
                        <TextField
                          label="Why should this be reviewed?"
                          placeholder="e.g. the site entrance has poor GPS reception"
                          value={exceptionReason}
                          onChange={(event) => setExceptionReason(event.target.value)}
                        />
                        <div className="flex gap-2">
                          <Button className="h-9" onClick={() => void handleRequestLocationException()} isLoading={isSubmitting} disabled={!exceptionReason.trim()}>
                            Submit
                          </Button>
                          <Button variant="ghost" className="h-9" onClick={() => setShowExceptionForm(false)}>
                            Cancel
                          </Button>
                        </div>
                      </div>
                    )}
                  </div>
                )}
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

          {myExceptions.length > 0 && (
            <div className="rounded-xl border border-border bg-surface-raised p-4">
              <p className="mb-2 text-sm font-medium text-content-primary">Your GPS exception requests</p>
              <ul className="flex flex-col gap-2">
                {myExceptions.map((exception) => (
                  <li key={exception.id} className="flex items-start justify-between gap-3 text-sm">
                    <div>
                      <p className="text-content-secondary">{exception.reason}</p>
                      <p className="text-xs text-content-tertiary">{new Date(exception.createdAt).toLocaleDateString()}</p>
                      {exception.reviewNotes && <p className="mt-1 text-xs text-content-tertiary">Supervisor note: {exception.reviewNotes}</p>}
                    </div>
                    <StatusBadge label={exception.status} tone={EXCEPTION_STATUS_TONE[exception.status]} />
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </PageContainer>
  );
}
