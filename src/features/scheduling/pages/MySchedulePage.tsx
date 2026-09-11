import { useMemo } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useShifts } from '@/features/scheduling/hooks/useShifts';
import type { Shift } from '@/features/scheduling/types/scheduling.types';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';

const STATUS_LABEL: Record<Shift['status'], string> = {
  scheduled: 'Scheduled',
  confirmed: 'Confirmed',
  cancelled: 'Cancelled',
  completed: 'Completed',
};

function formatRange(shift: Shift): string {
  const start = new Date(shift.startsAt);
  const end = new Date(shift.endsAt);
  const dateLabel = start.toLocaleDateString('en-ZA', { weekday: 'long', day: '2-digit', month: 'short', year: 'numeric' });
  const startTime = start.toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' });
  const endTime = end.toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' });
  const overnight = start.getDate() !== end.getDate();
  return `${dateLabel} · ${startTime}–${endTime}${overnight ? ' (+1 day)' : ''}`;
}

export function MySchedulePage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();
  const { sites } = useAllSites(employee?.tenantId);

  const range = useMemo(() => {
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(start);
    end.setDate(end.getDate() + 28);
    return { rangeStart: start.toISOString(), rangeEnd: end.toISOString() };
  }, []);

  const {
    shifts,
    isLoading: shiftsLoading,
    error: shiftsError,
  } = useShifts(employee?.tenantId, { employeeId: employee?.id, ...range });

  const siteName = (siteId: string) => sites.find((s) => s.id === siteId)?.name ?? 'Unknown site';

  const isLoading = employeeLoading || shiftsLoading;
  const upcoming = shifts.filter((s) => s.status !== 'cancelled');

  return (
    <PageContainer>
      <PageHeader title="My Schedule" description="Your upcoming shifts for the next four weeks." />

      <ErrorAlert message={employeeError ?? shiftsError} />

      {isLoading ? (
        <LoadingBlock label="Loading your schedule…" />
      ) : !employee ? (
        <p className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
          No employee record is linked to your account, so there is no schedule to show.
        </p>
      ) : upcoming.length === 0 ? (
        <p className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
          No upcoming shifts scheduled.
        </p>
      ) : (
        <div className="flex flex-col gap-2">
          {upcoming.map((shift) => (
            <div key={shift.id} className="rounded-card border border-border bg-surface-raised p-4">
              <p className="font-medium text-content-primary">{formatRange(shift)}</p>
              <p className="mt-1 text-sm text-content-secondary">
                {siteName(shift.siteId)}
                {' · '}
                {STATUS_LABEL[shift.status]}
              </p>
              {shift.notes && <p className="mt-1 text-sm text-content-tertiary">{shift.notes}</p>}
            </div>
          ))}
        </div>
      )}
    </PageContainer>
  );
}
