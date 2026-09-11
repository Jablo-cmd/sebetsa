import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useSitesForClient } from '@/features/orgStructure/hooks/useSites';
import { useContractsForClient } from '@/features/orgStructure/hooks/useContracts';

const CONTRACT_STATUS_CLASSES: Record<string, string> = {
  draft: 'text-content-tertiary',
  active: 'text-success-500',
  expired: 'text-warning-600 dark:text-warning-500',
  terminated: 'text-danger-600',
};

export function ClientDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { client, isLoading, error } = useClient(id);
  const { sites, isLoading: sitesLoading } = useSitesForClient(id);
  const { contracts, isLoading: contractsLoading } = useContractsForClient(id);

  if (isLoading) {
    return <FullScreenSpinner label="Loading client…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!client) {
    return (
      <FullScreenNotice
        title="Client not found"
        message="This client doesn't exist, or you don't have access to view it."
        action={
          <Link to="/clients" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Clients
          </Link>
        }
      />
    );
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/clients')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Clients
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{client.name}</h1>
            <p className="text-sm text-content-secondary">{client.industry ?? 'No industry on file'}</p>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
            {client.status}
          </span>
        </div>

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Primary contact</dt>
            <dd className="mt-1 text-sm text-content-primary">{client.primaryContactName ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Contact email</dt>
            <dd className="mt-1 text-sm text-content-primary">{client.primaryContactEmail ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Contact phone</dt>
            <dd className="mt-1 text-sm text-content-primary">{client.primaryContactPhone ?? '—'}</dd>
          </div>
        </dl>
      </div>

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Sites</h2>
          <Link to="/sites" className="focus-ring rounded text-xs font-medium text-brand-600 hover:underline">
            Manage sites
          </Link>
        </div>
        {sitesLoading ? (
          <p className="text-sm text-content-tertiary">Loading sites…</p>
        ) : sites.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No sites for this client yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {sites.map((site) => (
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

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Contracts</h2>
          <Link to="/contracts" className="focus-ring rounded text-xs font-medium text-brand-600 hover:underline">
            Manage contracts
          </Link>
        </div>
        {contractsLoading ? (
          <p className="text-sm text-content-tertiary">Loading contracts…</p>
        ) : contracts.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No contracts for this client yet.
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
