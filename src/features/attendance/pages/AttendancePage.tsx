import { useEffect, useState } from 'react';
import { usePermissions } from '@/hooks/usePermissions';
import { useAuth } from '@/features/auth/context/authContext';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useSitesList } from '@/features/attendance/hooks/useSitesList';
import { useAttendanceRoster } from '@/features/attendance/hooks/useAttendanceRoster';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import type { AttendanceStatus } from '@/features/attendance/types/attendance.types';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import { getDbErrorMessage } from '@/lib/dbErrors';

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}

const STATUS_OPTIONS: { value: AttendanceStatus; label: string }[] = [
  { value: 'present', label: 'Present' },
  { value: 'late', label: 'Late' },
  { value: 'absent', label: 'Absent' },
  { value: 'excused', label: 'Excused' },
];

const STATUS_BUTTON_CLASSES: Record<AttendanceStatus, string> = {
  present:
    'data-[active=true]:bg-success-500/15 data-[active=true]:text-success-500 data-[active=true]:border-success-500/40',
  absent:
    'data-[active=true]:bg-danger-50 data-[active=true]:text-danger-600 data-[active=true]:border-danger-500/40',
  late: 'data-[active=true]:bg-warning-50 data-[active=true]:text-warning-600 data-[active=true]:border-warning-500/40 dark:data-[active=true]:bg-warning-500/15 dark:data-[active=true]:text-warning-500',
  excused:
    'data-[active=true]:bg-brand-50 data-[active=true]:text-brand-700 data-[active=true]:border-brand-400 dark:data-[active=true]:bg-brand-500/15 dark:data-[active=true]:text-brand-300',
  unconfirmed: 'data-[active=true]:bg-surface-sunken data-[active=true]:text-content-tertiary',
};

export function AttendancePage() {
  const { can } = usePermissions();
  const { user } = useAuth();
  const canRecord = can('attendance.manage');
  const organization = useCurrentOrganization();
  const { sites } = useSitesList(organization?.id);

  const [siteId, setSiteId] = useState<string>('');
  const [date, setDate] = useState<string>(todayIsoDate());

  useEffect(() => {
    if (!siteId && sites.length > 0) setSiteId(sites[0]?.id ?? '');
  }, [sites, siteId]);

  const { roster, existingRecords, isLoading, error } = useAttendanceRoster(siteId || undefined, date);

  const [statuses, setStatuses] = useState<Record<string, AttendanceStatus>>({});
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const next: Record<string, AttendanceStatus> = {};
    for (const employee of roster) {
      const existing = existingRecords.find((record) => record.employeeId === employee.id);
      next[employee.id] = existing?.status ?? 'present';
    }
    setStatuses(next);
    setSaved(false);
  }, [roster, existingRecords]);

  const handleSave = async () => {
    if (!organization || !siteId || !user) return;
    setIsSaving(true);
    setSaveError(null);
    setSaved(false);
    try {
      await attendanceService.saveAttendance(
        organization.id,
        siteId,
        roster.map((employee) => ({
          employeeId: employee.id,
          status: statuses[employee.id] ?? 'present',
        })),
        user.id,
      );
      setSaved(true);
    } catch (err) {
      setSaveError(getDbErrorMessage(err, 'Failed to save attendance.'));
    } finally {
      setIsSaving(false);
    }
  };

  const selectedSiteName = sites.find((s) => s.id === siteId)?.name;
  const formattedDate = new Date(`${date}T00:00:00`).toLocaleDateString('en-ZA', {
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });

  if (!organization) {
    return (
      <PageContainer>
        <PageHeader title="Attendance" description="Record who was present at a site on a given date." />
        <NoActiveOrganizationNotice resource="attendance" />
      </PageContainer>
    );
  }

  return (
    <PageContainer>
      <PageHeader title="Attendance" description="Record who was present at a site on a given date." />

      <div className="flex flex-col gap-3 rounded-card border border-border bg-surface-raised p-4 sm:flex-row sm:items-end sm:gap-4">
        <div className="flex-1">
          <label htmlFor="attendance-site" className="mb-1.5 block text-sm font-medium text-content-primary">
            Site
          </label>
          {sites.length === 0 ? (
            <p className="text-sm text-content-tertiary">No sites yet.</p>
          ) : (
            <select
              id="attendance-site"
              value={siteId}
              onChange={(event) => setSiteId(event.target.value)}
              className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-64"
            >
              {sites.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          )}
        </div>

        <div>
          <label htmlFor="attendance-date" className="mb-1.5 block text-sm font-medium text-content-primary">
            Date
          </label>
          <input
            id="attendance-date"
            type="date"
            value={date}
            onChange={(event) => setDate(event.target.value)}
            className="focus-ring h-11 rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
          />
        </div>
      </div>

      <ErrorAlert message={error ?? saveError} />

      {siteId && (
        <div className="flex flex-col gap-3">
          {!isLoading && roster.length > 0 && (
            <p className="text-sm text-content-secondary">
              <span className="font-medium text-content-primary">{selectedSiteName ?? 'Site'}</span>
              {' · '}
              {formattedDate}
              {' · '}
              {roster.length} {roster.length === 1 ? 'employee' : 'employees'}
            </p>
          )}

          {isLoading ? (
            <div className="rounded-card border border-border bg-surface-raised">
              <LoadingBlock label="Loading roster…" />
            </div>
          ) : roster.length === 0 ? (
            <p className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
              No employees assigned to this site yet.
            </p>
          ) : (
            <>
              <div className="hidden md:block">
                <TableScrollContainer>
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
                        <th scope="col" className="px-4 py-3 font-medium">
                          Employee
                        </th>
                        <th scope="col" className="px-4 py-3 font-medium">
                          Employee #
                        </th>
                        <th scope="col" className="px-4 py-3 text-right font-medium">
                          Status
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {roster.map((employee) => (
                        <tr key={employee.id} className="border-b border-border last:border-0">
                          <td className="px-4 py-3 font-medium text-content-primary">
                            {employee.firstName} {employee.lastName}
                          </td>
                          <td className="px-4 py-3 text-content-secondary">{employee.employeeNumber}</td>
                          <td className="px-4 py-3">
                            <div className="flex justify-end gap-1.5">
                              {STATUS_OPTIONS.map((option) => (
                                <button
                                  key={option.value}
                                  type="button"
                                  disabled={!canRecord}
                                  data-active={statuses[employee.id] === option.value}
                                  onClick={() =>
                                    setStatuses((prev) => ({ ...prev, [employee.id]: option.value }))
                                  }
                                  className={cn(
                                    'focus-ring rounded-md border border-border-strong px-2.5 py-1 text-xs font-medium text-content-secondary transition-colors disabled:cursor-not-allowed disabled:opacity-60',
                                    STATUS_BUTTON_CLASSES[option.value],
                                  )}
                                >
                                  {option.label}
                                </button>
                              ))}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </TableScrollContainer>
              </div>

              <div className="flex flex-col gap-2 md:hidden">
                {roster.map((employee) => (
                  <div key={employee.id} className="rounded-card border border-border bg-surface-raised p-3.5">
                    <p className="text-sm font-medium text-content-primary">
                      {employee.firstName} {employee.lastName}
                    </p>
                    <p className="text-xs text-content-tertiary">{employee.employeeNumber}</p>
                    <div className="mt-2.5 flex gap-1.5">
                      {STATUS_OPTIONS.map((option) => (
                        <button
                          key={option.value}
                          type="button"
                          disabled={!canRecord}
                          data-active={statuses[employee.id] === option.value}
                          onClick={() => setStatuses((prev) => ({ ...prev, [employee.id]: option.value }))}
                          className={cn(
                            'focus-ring flex-1 rounded-md border border-border-strong px-2.5 py-2 text-xs font-medium text-content-secondary transition-colors disabled:cursor-not-allowed disabled:opacity-60',
                            STATUS_BUTTON_CLASSES[option.value],
                          )}
                        >
                          {option.label}
                        </button>
                      ))}
                    </div>
                  </div>
                ))}
              </div>

              {canRecord && (
                <div className="flex items-center justify-end gap-3 rounded-card border border-border bg-surface-raised px-4 py-3">
                  {saved && <span className="text-sm text-success-500">Attendance saved.</span>}
                  <div className="w-full sm:w-auto sm:min-w-[9rem]">
                    <Button type="button" onClick={() => void handleSave()} isLoading={isSaving}>
                      Save attendance
                    </Button>
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      )}
    </PageContainer>
  );
}
