import { useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { useSiteWorkforceOverview } from '@/features/siteOperations/hooks/useSiteWorkforceOverview';
import { siteOperationsService } from '@/features/siteOperations/services/siteOperationsService';
import type { StaffingRequirement } from '@/features/siteOperations/types/siteOperations.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** Operational visibility for one site at a time — the site picker itself
 * is already scoped by existing sites RLS, so a site_manager naturally
 * sees only their own site(s) here and an operations_manager sees theirs,
 * with no separate role-branching UI required. */
export function SiteOperationsPage() {
  const { can } = usePermissions();
  const canManage = can('site_assignment.manage');
  const organization = useCurrentOrganization();
  const { sites, isLoading: sitesLoading } = useAllSites(organization?.id);
  const [siteId, setSiteId] = useState('');

  useEffect(() => {
    if (!siteId && sites.length > 0) setSiteId(sites[0]?.id ?? '');
  }, [sites, siteId]);

  const { overview, isLoading: overviewLoading, error: overviewError, refetch } = useSiteWorkforceOverview(organization?.id, siteId || undefined);

  const [requirements, setRequirements] = useState<StaffingRequirement[]>([]);
  const [newLabel, setNewLabel] = useState('');
  const [newCount, setNewCount] = useState('');
  const [reqError, setReqError] = useState<string | null>(null);
  const [isSavingReq, setIsSavingReq] = useState(false);

  useEffect(() => {
    if (!organization || !siteId) return;
    void siteOperationsService.getStaffingRequirements(organization.id, siteId).then(setRequirements);
  }, [organization, siteId]);

  if (!organization) return <NoActiveOrganizationNotice resource="site operations" />;

  const handleAddRequirement = async () => {
    if (!organization || !siteId || !newLabel.trim() || !newCount) return;
    setIsSavingReq(true);
    setReqError(null);
    try {
      const saved = await siteOperationsService.upsertStaffingRequirement(organization.id, siteId, newLabel.trim(), Number(newCount));
      setRequirements((prev) => [...prev.filter((r) => r.label !== saved.label), saved]);
      setNewLabel('');
      setNewCount('');
      void refetch();
    } catch (err) {
      setReqError(getDbErrorMessage(err, 'Failed to save the staffing requirement.'));
    } finally {
      setIsSavingReq(false);
    }
  };

  const isLoading = sitesLoading || overviewLoading;
  const shortage = overview?.requiredCount != null ? overview.requiredCount - overview.presentCount : null;

  return (
    <PageContainer>
      <PageHeader title="Site Operations" description="Workforce deployment, staffing, and staffing gaps for one site at a time." />

      <ErrorAlert message={overviewError} />

      <div className="mt-4">
        <label htmlFor="site-picker" className="mb-1.5 block text-sm font-medium text-content-primary">
          Site
        </label>
        <select
          id="site-picker"
          className="focus-ring h-11 w-full max-w-sm rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
          value={siteId}
          onChange={(event) => setSiteId(event.target.value)}
        >
          {sites.map((site) => (
            <option key={site.id} value={site.id}>
              {site.name}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <LoadingBlock label="Loading site overview…" />
      ) : !siteId ? (
        <p className="mt-6 text-sm text-content-secondary">No sites available.</p>
      ) : (
        overview && (
          <>
            <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
              <StatCard label="Assigned" value={overview.assignedCount} />
              <StatCard label="Scheduled today" value={overview.scheduledTodayCount} />
              <StatCard label="Present" value={overview.presentCount} tone="success" />
              <StatCard label="Late" value={overview.lateCount} tone="warning" />
              <StatCard label="Absent" value={overview.absentCount} tone="danger" />
              <StatCard label="Open tasks" value={overview.openTasksCount} />
              {overview.requiredCount != null && (
                <StatCard label="Required" value={overview.requiredCount} />
              )}
              {shortage !== null && (
                <StatCard label={shortage > 0 ? 'Shortage' : 'Fully staffed'} value={Math.abs(shortage)} tone={shortage > 0 ? 'danger' : 'success'} />
              )}
            </div>

            {canManage && (
              <div className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
                <h2 className="text-sm font-semibold text-content-primary">Staffing requirements</h2>
                <div className="mt-3 flex flex-col gap-2">
                  {requirements.map((req) => (
                    <div key={req.id} className="flex items-center justify-between text-sm">
                      <span className="text-content-secondary">{req.label}</span>
                      <span className="font-medium text-content-primary">{req.requiredCount}</span>
                    </div>
                  ))}
                </div>
                <div className="mt-3 flex flex-wrap items-end gap-2">
                  <TextField label="Label" placeholder="e.g. Day shift guards" value={newLabel} onChange={(event) => setNewLabel(event.target.value)} />
                  <TextField label="Required count" type="number" min="0" value={newCount} onChange={(event) => setNewCount(event.target.value)} />
                  <Button onClick={() => void handleAddRequirement()} isLoading={isSavingReq} disabled={!newLabel.trim() || !newCount}>
                    Save
                  </Button>
                </div>
                {reqError && <p className="mt-2 text-sm font-medium text-danger-600">{reqError}</p>}
              </div>
            )}
          </>
        )
      )}
    </PageContainer>
  );
}

function StatCard({ label, value, tone }: { label: string; value: number; tone?: 'success' | 'warning' | 'danger' }) {
  const toneClass =
    tone === 'success'
      ? 'text-success-600'
      : tone === 'warning'
        ? 'text-warning-600'
        : tone === 'danger'
          ? 'text-danger-600'
          : 'text-content-primary';
  return (
    <div className="rounded-xl border border-border bg-surface-raised p-4">
      <p className="text-xs text-content-secondary">{label}</p>
      <p className={`mt-1 text-2xl font-bold ${toneClass}`}>{value}</p>
    </div>
  );
}
