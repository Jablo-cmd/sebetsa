import { useNavigate, useParams, Link } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useRegion } from '@/features/orgStructure/hooks/useRegions';
import { useSitesForRegion } from '@/features/orgStructure/hooks/useSites';

export function RegionDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const { region, isLoading, error } = useRegion(id);
  const { sites, isLoading: sitesLoading } = useSitesForRegion(id);

  if (isLoading) {
    return <FullScreenSpinner label="Loading region…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!region) {
    return (
      <FullScreenNotice
        title="Region not found"
        message="This region doesn't exist, or you don't have access to view it."
        action={
          <Link to="/regions" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Regions
          </Link>
        }
      />
    );
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/regions')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Regions
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{region.name}</h1>
            <p className="text-sm text-content-secondary">{region.code ?? 'No code'}</p>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
            {region.status}
          </span>
        </div>
      </div>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Sites in this region</h2>
        {sitesLoading ? (
          <p className="text-sm text-content-tertiary">Loading sites…</p>
        ) : sites.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No sites in this region yet.
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

      {canManage && (
        <p className="text-xs text-content-tertiary">
          Edit this region's name or code, or archive it, from the{' '}
          <Link to="/regions" className="text-brand-600 hover:underline">
            Regions list
          </Link>
          .
        </p>
      )}
    </div>
  );
}
