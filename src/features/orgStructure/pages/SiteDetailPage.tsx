import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { useSite } from '@/features/orgStructure/hooks/useSites';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { SiteFormModal } from '@/features/orgStructure/components/SiteFormModal';
import { siteService } from '@/features/orgStructure/services/siteService';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import type { EntityStatus } from '@/features/orgStructure/types/orgStructure.types';
import { usePermissions } from '@/hooks/usePermissions';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useRegion, useRegions } from '@/features/orgStructure/hooks/useRegions';
import { useContractsForSite } from '@/features/orgStructure/hooks/useContracts';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useSiteAssignmentsForSite } from '@/features/siteAssignments/hooks/useSiteAssignments';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';

const ENTITY_STATUS_OPTIONS: EntityStatus[] = ['active', 'inactive', 'onboarding', 'offboarded'];

const CONTRACT_STATUS_CLASSES: Record<string, string> = {
  draft: 'text-content-tertiary',
  active: 'text-success-500',
  expired: 'text-warning-600 dark:text-warning-500',
  terminated: 'text-danger-600',
};

export function SiteDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const organization = useCurrentOrganization();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const { site, isLoading, error, refetch } = useSite(id);
  const { clients: allClients } = useAllClients(organization?.id);
  const { regions } = useRegions(organization?.id);
  const [isEditOpen, setIsEditOpen] = useState(false);
  const [isChangingStatus, setIsChangingStatus] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [employeesError, setEmployeesError] = useState<string | null>(null);
  const { client } = useClient(site?.clientId);
  const { region } = useRegion(site?.regionId ?? undefined);
  const { contracts, isLoading: contractsLoading } = useContractsForSite(id);
  const { assignments: workforce, isLoading: workforceLoading } = useSiteAssignmentsForSite(organization?.id, id);
  const [employees, setEmployees] = useState<Map<string, EmployeeCandidate>>(new Map());

  useEffect(() => {
    const ids = [...new Set(workforce.map((a) => a.employeeId))];
    if (ids.length === 0) {
      setEmployees(new Map());
      return;
    }
    let cancelled = false;
    setEmployeesError(null);
    employeeService
      .getEmployeeCandidatesByIds(ids)
      .then((results) => {
        if (!cancelled) setEmployees(new Map(results.map((e) => [e.id, e])));
      })
      .catch((err: unknown) => {
        if (!cancelled) setEmployeesError(getDbErrorMessage(err, 'Failed to load the workforce names.'));
      });
    return () => {
      cancelled = true;
    };
  }, [workforce]);

  const handleStatusChange = async (status: EntityStatus) => {
    if (!site) return;
    setStatusError(null);
    setIsChangingStatus(true);
    try {
      await siteService.updateSite(site.id, { status });
      await refetch();
    } catch (err) {
      setStatusError(getDbErrorMessage(err, 'Failed to update the site.'));
    } finally {
      setIsChangingStatus(false);
    }
  };

  if (isLoading) {
    return <FullScreenSpinner label="Loading site…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!site) {
    return (
      <FullScreenNotice
        title="Site not found"
        message="This site doesn't exist, or you don't have access to view it."
        action={
          <Link to="/sites" className="focus-ring rounded text-sm font-medium text-brand-600 dark:text-brand-300 hover:underline">
            Back to Sites
          </Link>
        }
      />
    );
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/sites')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Sites
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{site.name}</h1>
            <p className="text-sm text-content-secondary">{site.address ?? 'No address on file'}</p>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
            {site.status}
          </span>
        </div>

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Client</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {client ? (
                <Link to={`/clients/${client.id}`} className="text-brand-600 dark:text-brand-300 hover:underline">
                  {client.name}
                </Link>
              ) : (
                '—'
              )}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Region</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {region ? (
                <Link to={`/regions/${region.id}`} className="text-brand-600 dark:text-brand-300 hover:underline">
                  {region.name}
                </Link>
              ) : (
                '—'
              )}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Site type</dt>
            <dd className="mt-1 text-sm text-content-primary">{site.siteType ?? '—'}</dd>
          </div>
        </dl>

        <ErrorAlert message={statusError} />

        {canManage && (
          <div className="mt-6 flex flex-wrap gap-2 border-t border-border pt-5">
            <Button type="button" variant="secondary" onClick={() => setIsEditOpen(true)}>
              Edit details
            </Button>
            <select
              aria-label="Site status"
              value={site.status}
              disabled={isChangingStatus}
              onChange={(event) => void handleStatusChange(event.target.value as EntityStatus)}
              className="focus-ring h-10 rounded-lg border border-border-strong bg-surface-raised px-3 text-sm font-medium capitalize text-content-primary"
            >
              {ENTITY_STATUS_OPTIONS.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      {organization && (
        <SiteFormModal
          isOpen={isEditOpen}
          onClose={() => setIsEditOpen(false)}
          tenantId={organization.id}
          site={site}
          clients={allClients}
          regions={regions}
          onSaved={() => void refetch()}
        />
      )}

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Current Workforce</h2>
          <Link to="/site-assignments" className="focus-ring rounded text-xs font-medium text-brand-600 dark:text-brand-300 hover:underline">
            Manage assignments
          </Link>
        </div>
        <ErrorAlert message={employeesError} />
        {workforceLoading ? (
          <p className="text-sm text-content-tertiary">Loading workforce…</p>
        ) : workforce.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No employees currently assigned to this site.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {workforce.map((assignment) => {
              const employee = employees.get(assignment.employeeId);
              return (
                <Link
                  key={assignment.id}
                  to={`/employees/${assignment.employeeId}`}
                  className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
                >
                  <span className="font-medium text-content-primary">
                    {employee ? `${employee.firstName} ${employee.lastName}` : '—'}
                  </span>
                  {assignment.roleOnSite && <span className="text-xs text-content-tertiary">{assignment.roleOnSite}</span>}
                </Link>
              );
            })}
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Contracts covering this site</h2>
          <Link to="/contracts" className="focus-ring rounded text-xs font-medium text-brand-600 dark:text-brand-300 hover:underline">
            Manage contracts
          </Link>
        </div>
        {contractsLoading ? (
          <p className="text-sm text-content-tertiary">Loading contracts…</p>
        ) : contracts.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No contracts cover this site yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {contracts.map((contract) => (
              <Link
                key={contract.id}
                to={`/contracts/${contract.id}`}
                className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
              >
                <span className="font-medium text-content-primary">{contract.contractNumber}</span>
                <span className={`text-xs font-medium capitalize ${CONTRACT_STATUS_CLASSES[contract.status] ?? 'text-content-tertiary'}`}>
                  {contract.status}
                </span>
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
