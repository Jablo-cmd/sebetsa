import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { useSite } from '@/features/orgStructure/hooks/useSites';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useRegion } from '@/features/orgStructure/hooks/useRegions';
import { useContractsForSite } from '@/features/orgStructure/hooks/useContracts';

const CONTRACT_STATUS_CLASSES: Record<string, string> = {
  draft: 'text-content-tertiary',
  active: 'text-success-500',
  expired: 'text-warning-600 dark:text-warning-500',
  terminated: 'text-danger-600',
};

export function SiteDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { site, isLoading, error } = useSite(id);
  const { client } = useClient(site?.clientId);
  const { region } = useRegion(site?.regionId ?? undefined);
  const { contracts, isLoading: contractsLoading } = useContractsForSite(id);

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
          <Link to="/sites" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
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
                <Link to={`/clients/${client.id}`} className="text-brand-600 hover:underline">
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
                <Link to={`/regions/${region.id}`} className="text-brand-600 hover:underline">
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
      </div>

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Contracts covering this site</h2>
          <Link to="/contracts" className="focus-ring rounded text-xs font-medium text-brand-600 hover:underline">
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
