import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { useShifts } from '@/features/scheduling/hooks/useShifts';
import { useShiftDefinitions } from '@/features/scheduling/hooks/useShiftDefinitions';
import { attendanceService } from '@/features/attendance/services/attendanceService';
import { employeeService } from '@/features/employees/services/employeeService';
import type { RosterEmployee } from '@/features/attendance/types/attendance.types';
import { ScheduleWeekGrid, type ScheduleGridEmployee } from '@/features/scheduling/components/ScheduleWeekGrid';
import { ShiftFormModal } from '@/features/scheduling/components/ShiftFormModal';
import type { Shift } from '@/features/scheduling/types/scheduling.types';
import { startOfWeek, addDays, weekDays, weekRangeIso, formatWeekLabel } from '@/features/scheduling/utils/weekRange';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function SchedulePage() {
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('scheduling.manage');
  const organization = useCurrentOrganization();
  const { sites } = useAllSites(organization?.id);
  const { shiftDefinitions } = useShiftDefinitions(organization?.id);

  const [siteId, setSiteId] = useState('');
  const [weekAnchor, setWeekAnchor] = useState(() => startOfWeek(new Date()));

  useEffect(() => {
    if (!siteId && sites.length > 0) setSiteId(sites[0]?.id ?? '');
  }, [sites, siteId]);

  const days = useMemo(() => weekDays(weekAnchor), [weekAnchor]);
  const range = useMemo(() => weekRangeIso(weekAnchor), [weekAnchor]);

  const { shifts, isLoading: shiftsLoading, error: shiftsError, refetch: refetchShifts } = useShifts(organization?.id, {
    siteId: siteId || undefined,
    rangeStart: range.rangeStart,
    rangeEnd: range.rangeEnd,
  });

  const [roster, setRoster] = useState<RosterEmployee[]>([]);
  const [rosterLoading, setRosterLoading] = useState(true);
  const [rosterError, setRosterError] = useState<string | null>(null);
  const [extraEmployees, setExtraEmployees] = useState<ScheduleGridEmployee[]>([]);

  useEffect(() => {
    if (!siteId) {
      setRoster([]);
      setRosterLoading(false);
      return;
    }
    let cancelled = false;
    setRosterLoading(true);
    setRosterError(null);
    attendanceService
      .getSiteRoster(siteId)
      .then((result) => {
        if (!cancelled) setRoster(result);
      })
      .catch((err: unknown) => {
        if (!cancelled) setRosterError(getDbErrorMessage(err, 'Failed to load the site roster.'));
      })
      .finally(() => {
        if (!cancelled) setRosterLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [siteId]);

  // A shift can exist for an employee not currently assigned to this site
  // (one-off/relief cover — see the Phase G architecture, §6) — the roster
  // alone would silently hide them from the grid.
  useEffect(() => {
    const rosterIds = new Set(roster.map((r) => r.id));
    const missingIds = [...new Set(shifts.map((s) => s.employeeId))].filter((id) => !rosterIds.has(id));
    if (missingIds.length === 0) {
      setExtraEmployees([]);
      return;
    }
    let cancelled = false;
    void employeeService.getEmployeeCandidatesByIds(missingIds).then((results) => {
      if (!cancelled) setExtraEmployees(results);
    });
    return () => {
      cancelled = true;
    };
  }, [roster, shifts]);

  const gridEmployees: ScheduleGridEmployee[] = useMemo(
    () => [...roster.map((r) => ({ id: r.id, firstName: r.firstName, lastName: r.lastName })), ...extraEmployees],
    [roster, extraEmployees],
  );

  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingShift, setEditingShift] = useState<Shift | null>(null);
  const [initialEmployeeId, setInitialEmployeeId] = useState<string | undefined>(undefined);
  const [initialDate, setInitialDate] = useState<string | undefined>(undefined);

  const openCreate = (employeeId: string, date: Date) => {
    setEditingShift(null);
    setInitialEmployeeId(employeeId);
    setInitialDate(`${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`);
    setIsFormOpen(true);
  };

  const openEdit = (shift: Shift) => {
    setEditingShift(shift);
    setInitialEmployeeId(undefined);
    setInitialDate(undefined);
    setIsFormOpen(true);
  };

  const selectedSiteName = sites.find((s) => s.id === siteId)?.name;

  return (
    <PageContainer>
      <PageHeader
        title="Schedule"
        description="Who is scheduled to work, where, and when — by site and week."
        action={
          canManage && (
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="secondary" onClick={() => navigate('/schedule/definitions')}>
                Shift definitions
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={shiftsError ?? rosterError} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="the schedule" />
      ) : (
        <>
          <div className="flex flex-col gap-3 rounded-card border border-border bg-surface-raised p-4 sm:flex-row sm:items-end sm:justify-between sm:gap-4">
            <div className="flex-1 sm:max-w-xs">
              <label htmlFor="schedule-site" className="mb-1.5 block text-sm font-medium text-content-primary">
                Site
              </label>
              {sites.length === 0 ? (
                <p className="text-sm text-content-tertiary">No sites yet.</p>
              ) : (
                <select
                  id="schedule-site"
                  value={siteId}
                  onChange={(event) => setSiteId(event.target.value)}
                  className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
                >
                  {sites.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name}
                    </option>
                  ))}
                </select>
              )}
            </div>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => setWeekAnchor((prev) => addDays(prev, -7))}
                className="focus-ring rounded-md border border-border-strong px-3 py-2 text-sm font-medium text-content-secondary hover:bg-surface-sunken"
              >
                ← Prev
              </button>
              <span className="min-w-[10rem] text-center text-sm font-medium text-content-primary">
                {formatWeekLabel(weekAnchor)}
              </span>
              <button
                type="button"
                onClick={() => setWeekAnchor((prev) => addDays(prev, 7))}
                className="focus-ring rounded-md border border-border-strong px-3 py-2 text-sm font-medium text-content-secondary hover:bg-surface-sunken"
              >
                Next →
              </button>
              <button
                type="button"
                onClick={() => setWeekAnchor(startOfWeek(new Date()))}
                className="focus-ring rounded-md px-3 py-2 text-sm font-medium text-brand-600 hover:bg-brand-50 dark:hover:bg-brand-500/10"
              >
                Today
              </button>
            </div>
          </div>

          {siteId && (
            <>
              {!shiftsLoading && !rosterLoading && (
                <p className="text-sm text-content-secondary">
                  <span className="font-medium text-content-primary">{selectedSiteName ?? 'Site'}</span>
                  {' · '}
                  {gridEmployees.length} {gridEmployees.length === 1 ? 'employee' : 'employees'}
                  {' · '}
                  {shifts.filter((s) => s.status !== 'cancelled').length} scheduled shift
                  {shifts.filter((s) => s.status !== 'cancelled').length === 1 ? '' : 's'} this week
                </p>
              )}

              {shiftsLoading || rosterLoading ? (
                <div className="rounded-card border border-border bg-surface-raised">
                  <LoadingBlock label="Loading schedule…" />
                </div>
              ) : (
                <ScheduleWeekGrid
                  days={days}
                  employees={gridEmployees}
                  shifts={shifts}
                  canManage={canManage}
                  onCreateShift={openCreate}
                  onEditShift={openEdit}
                />
              )}
            </>
          )}

          {organization && siteId && (
            <ShiftFormModal
              isOpen={isFormOpen}
              onClose={() => setIsFormOpen(false)}
              tenantId={organization.id}
              shift={editingShift}
              sites={sites}
              shiftDefinitions={shiftDefinitions}
              initialSiteId={siteId}
              initialEmployeeId={initialEmployeeId}
              initialDate={initialDate}
              onSaved={() => void refetchShifts()}
            />
          )}
        </>
      )}
    </PageContainer>
  );
}
