import { MaintenanceLogModal } from '@/features/assets/components/MaintenanceLogModal';
import { usePermissions } from '@/hooks/usePermissions';
import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { useSitesList } from '@/features/attendance/hooks/useSitesList';
import { useEmployeeNames } from '@/features/employees/hooks/useEmployeeNames';
import { AssignAssetModal } from '@/features/assets/components/AssignAssetModal';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { assetService } from '@/features/assets/services/assetService';
import { ASSET_STATUS_LABELS } from '@/features/assets/types/assets.types';
import type { Asset } from '@/features/assets/types/assets.types';
import type { AssetStatusEnum } from '@/lib/dbTypes';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_TONES: Record<AssetStatusEnum, StatusTone> = {
  available: 'success',
  assigned: 'info',
  maintenance: 'warning',
  lost: 'danger',
  damaged: 'danger',
  retired: 'neutral',
  disposed: 'neutral',
};

/** Asset register and lifecycle. Each row offers only the moves the status
 * allows (mirroring the database's asset state machine): assign to / return
 * from an employee, maintenance, damaged/lost, retire, dispose. The database
 * enforces the same rules and records every change in the audit trail. */
const ROW_ACTIONS: Partial<Record<AssetStatusEnum, { label: string; to: AssetStatusEnum }[]>> = {
  available: [
    { label: 'Send to maintenance', to: 'maintenance' },
    { label: 'Retire', to: 'retired' },
  ],
  assigned: [
    { label: 'Report damaged', to: 'damaged' },
    { label: 'Report lost', to: 'lost' },
  ],
  maintenance: [
    { label: 'Return to service', to: 'available' },
    { label: 'Retire', to: 'retired' },
  ],
  damaged: [
    { label: 'Send to maintenance', to: 'maintenance' },
    { label: 'Retire', to: 'retired' },
  ],
  lost: [
    { label: 'Mark recovered', to: 'available' },
    { label: 'Retire', to: 'retired' },
  ],
  retired: [{ label: 'Dispose', to: 'disposed' }],
};

export function AssetsPage() {
  const organization = useCurrentOrganization();
  const [assets, setAssets] = useState<Asset[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { sites } = useSitesList(organization?.id);
  const [siteId, setSiteId] = useState('');
  const [assigning, setAssigning] = useState<Asset | null>(null);
  const [maintenanceFor, setMaintenanceFor] = useState<Asset | null>(null);
  const { can } = usePermissions();
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

  const custodianNames = useEmployeeNames(assets.map((asset) => asset.custodianEmployeeId).filter((id): id is string => Boolean(id)));

  if (!organization) return <NoActiveOrganizationNotice resource="assets" />;

  const handleCreate = async () => {
    if (!assetNumber.trim() || !name.trim() || !category.trim()) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await assetService.createAsset({ tenantId: organization.id, assetNumber: assetNumber.trim(), name: name.trim(), category: category.trim(), siteId: siteId || undefined });
      setSiteId('');
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

  const handleReturn = async (assetId: string) => {
    setError(null);
    try {
      await assetService.returnAsset(assetId);
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to return the asset.'));
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
          <label className="flex flex-col gap-1 text-sm">
            Site
            <select value={siteId} onChange={(event) => setSiteId(event.target.value)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
              <option value="">No specific site</option>
              {sites.map((site) => (
                <option key={site.id} value={site.id}>{site.name}</option>
              ))}
            </select>
          </label>
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
                <th className="px-3 py-2">Site</th>
                <th className="px-3 py-2">Custodian</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {assets.map((asset) => (
                <tr key={asset.id} className="border-b border-border last:border-0">
                  <td className="px-3 py-2.5">{asset.assetNumber} — {asset.name}</td>
                  <td className="px-3 py-2.5">{asset.category}</td>
                  <td className="px-3 py-2.5">{asset.siteId ? sites.find((site) => site.id === asset.siteId)?.name ?? '—' : '—'}</td>
                  <td className="px-3 py-2.5">{asset.custodianEmployeeId ? custodianNames[asset.custodianEmployeeId] ?? '—' : '—'}</td>
                  <td className="px-3 py-2.5">
                    <StatusBadge label={ASSET_STATUS_LABELS[asset.status]} tone={STATUS_TONES[asset.status]} />
                  </td>
                  <td className="px-3 py-2.5 text-right">
                    <Button variant="ghost" aria-label={`Maintenance log for ${asset.assetNumber}`} onClick={() => setMaintenanceFor(asset)}>Maintenance log</Button>
                    {asset.status === 'available' && (
                      <Button variant="ghost" onClick={() => setAssigning(asset)}>Assign</Button>
                    )}
                    {asset.status === 'assigned' && (
                      <Button variant="ghost" onClick={() => void handleReturn(asset.id)}>Return</Button>
                    )}
                    {(ROW_ACTIONS[asset.status] ?? []).map((action) => (
                      <Button key={action.label} variant="ghost" onClick={() => void handleTransition(asset.id, action.to)}>
                        {action.label}
                      </Button>
                    ))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <MaintenanceLogModal
        isOpen={maintenanceFor !== null}
        onClose={() => setMaintenanceFor(null)}
        asset={maintenanceFor}
        canRecord={can('asset.manage')}
      />
      <AssignAssetModal
        isOpen={assigning !== null}
        onClose={() => setAssigning(null)}
        asset={assigning}
        tenantId={organization.id}
        onAssigned={() => void load()}
      />
    </PageContainer>
  );
}
