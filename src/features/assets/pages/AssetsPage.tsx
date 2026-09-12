import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { assetService } from '@/features/assets/services/assetService';
import { ASSET_STATUS_LABELS } from '@/features/assets/types/assets.types';
import type { Asset } from '@/features/assets/types/assets.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_CLASSES: Record<string, string> = {
  available: 'bg-success-50 text-success-700 dark:bg-success-500/15 dark:text-success-200',
  assigned: 'bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-200',
  maintenance: 'bg-warning-50 text-warning-700 dark:bg-warning-500/15 dark:text-warning-200',
  lost: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
  damaged: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
  retired: 'bg-surface-sunken text-content-tertiary',
  disposed: 'bg-surface-sunken text-content-tertiary',
};

/** Asset register: create, view lifecycle status. Assignment/return happen
 * via RPC from a per-row action rather than a separate modal, keeping the
 * page focused for this operational-management-tier audience. */
export function AssetsPage() {
  const organization = useCurrentOrganization();
  const [assets, setAssets] = useState<Asset[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [assetNumber, setAssetNumber] = useState('');
  const [name, setName] = useState('');
  const [category, setCategory] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      setAssets(await assetService.getAssets(organization.id));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load assets.'));
    } finally {
      setIsLoading(false);
    }
  }, [organization]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!organization) return <NoActiveOrganizationNotice resource="assets" />;

  const handleCreate = async () => {
    if (!assetNumber.trim() || !name.trim() || !category.trim()) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await assetService.createAsset({ tenantId: organization.id, assetNumber: assetNumber.trim(), name: name.trim(), category: category.trim() });
      setAssetNumber('');
      setName('');
      setCategory('');
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the asset.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleTransition = async (assetId: string, status: Asset['status']) => {
    setError(null);
    try {
      await assetService.transitionAssetStatus(assetId, status);
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to update the asset status.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Assets" description="Operational asset register — equipment, machinery, devices, uniforms." />

      <ErrorAlert message={error} />

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <p className="text-sm font-medium text-content-primary">Add an asset</p>
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <TextField label="Asset number" placeholder="AST-001" value={assetNumber} onChange={(event) => setAssetNumber(event.target.value)} />
          <TextField label="Name" placeholder="Floor buffer" value={name} onChange={(event) => setName(event.target.value)} />
          <TextField label="Category" placeholder="equipment" value={category} onChange={(event) => setCategory(event.target.value)} />
          <Button onClick={() => void handleCreate()} isLoading={isSubmitting} disabled={!assetNumber.trim() || !name.trim() || !category.trim()}>
            Add
          </Button>
        </div>
      </div>

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : assets.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No assets registered yet.</p>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-border text-xs uppercase text-content-secondary">
                <th className="px-3 py-2">Asset</th>
                <th className="px-3 py-2">Category</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {assets.map((asset) => (
                <tr key={asset.id} className="border-b border-border last:border-0">
                  <td className="px-3 py-2.5">{asset.assetNumber} — {asset.name}</td>
                  <td className="px-3 py-2.5">{asset.category}</td>
                  <td className="px-3 py-2.5">
                    <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_CLASSES[asset.status] ?? ''}`}>{ASSET_STATUS_LABELS[asset.status]}</span>
                  </td>
                  <td className="px-3 py-2.5 text-right">
                    {asset.status === 'available' && (
                      <Button variant="ghost" onClick={() => void handleTransition(asset.id, 'maintenance')}>Send to maintenance</Button>
                    )}
                    {asset.status === 'maintenance' && (
                      <Button variant="ghost" onClick={() => void handleTransition(asset.id, 'available')}>Return to service</Button>
                    )}
                    {asset.status === 'retired' && (
                      <Button variant="ghost" onClick={() => void handleTransition(asset.id, 'disposed')}>Dispose</Button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </PageContainer>
  );
}
