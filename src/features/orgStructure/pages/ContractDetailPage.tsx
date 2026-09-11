import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useContract } from '@/features/orgStructure/hooks/useContracts';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useContractSiteIds } from '@/features/orgStructure/hooks/useContracts';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { contractService } from '@/features/orgStructure/services/contractService';
import { ContractFormModal } from '@/features/orgStructure/components/ContractFormModal';
import type { ContractStatus } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_OPTIONS: { value: ContractStatus; label: string }[] = [
  { value: 'draft', label: 'Draft' },
  { value: 'active', label: 'Active' },
  { value: 'expired', label: 'Expired' },
  { value: 'terminated', label: 'Terminated' },
];

export function ContractDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { contract, isLoading, error, refetch } = useContract(id);
  const { client } = useClient(contract?.clientId);
  const { siteIds } = useContractSiteIds(id);
  const { sites: allSites } = useAllSites(organization?.id);
  const { clients } = useAllClients(organization?.id);

  const [isEditOpen, setIsEditOpen] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [isChangingStatus, setIsChangingStatus] = useState(false);

  if (isLoading) {
    return <FullScreenSpinner label="Loading contract…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!contract) {
    return (
      <FullScreenNotice
        title="Contract not found"
        message="This contract doesn't exist, or you don't have access to view it."
        action={
          <Link to="/contracts" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Contracts
          </Link>
        }
      />
    );
  }

  const coveredSites = allSites.filter((s) => siteIds.includes(s.id));

  const handleStatusChange = async (status: ContractStatus) => {
    setStatusError(null);
    setIsChangingStatus(true);
    try {
      await contractService.updateContractStatus(contract.id, status);
      await refetch();
    } catch (err) {
      setStatusError(getDbErrorMessage(err, 'Failed to update contract status.'));
    } finally {
      setIsChangingStatus(false);
    }
  };

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/contracts')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Contracts
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{contract.contractNumber}</h1>
            <p className="text-sm text-content-secondary">
              {client ? (
                <Link to={`/clients/${client.id}`} className="text-brand-600 hover:underline">
                  {client.name}
                </Link>
              ) : (
                'No client'
              )}
            </p>
          </div>
          {canManage ? (
            <select
              aria-label="Contract status"
              value={contract.status}
              disabled={isChangingStatus}
              onChange={(event) => void handleStatusChange(event.target.value as ContractStatus)}
              className="focus-ring h-10 rounded-lg border border-border-strong bg-surface-raised px-3 text-sm font-medium capitalize text-content-primary"
            >
              {STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          ) : (
            <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
              {contract.status}
            </span>
          )}
        </div>

        <ErrorAlert message={statusError} />

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Start date</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.startDate}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">End date</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.endDate ?? '—'}</dd>
          </div>
          <div className="sm:col-span-2">
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">SLA notes</dt>
            <dd className="mt-1 whitespace-pre-wrap text-sm text-content-primary">{contract.slaNotes ?? '—'}</dd>
          </div>
        </dl>

        {canManage && (
          <div className="mt-6 border-t border-border pt-5">
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" onClick={() => setIsEditOpen(true)}>
                Edit details
              </Button>
            </div>
          </div>
        )}
      </div>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Sites covered</h2>
        {coveredSites.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No sites linked to this contract yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {coveredSites.map((site) => (
              <Link
                key={site.id}
                to={`/sites/${site.id}`}
                className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
              >
                <span className="font-medium text-content-primary">{site.name}</span>
                <span className="text-xs capitalize text-content-tertiary">{site.status}</span>
              </Link>
            ))}
          </div>
        )}
      </section>

      {organization && (
        <ContractFormModal
          isOpen={isEditOpen}
          onClose={() => setIsEditOpen(false)}
          tenantId={organization.id}
          contract={contract}
          clients={clients}
          sites={allSites}
          onSaved={() => void refetch()}
        />
      )}
    </div>
  );
}
