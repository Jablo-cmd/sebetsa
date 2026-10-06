import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { inventoryService } from '@/features/assets/services/inventoryService';
import type { InventoryItem } from '@/features/assets/types/assets.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** Inventory: items + a movement ledger, viewed one site at a time. Balances
 * are always derived by the database (get_inventory_balances, one request for
 * the whole site) — never cached as an independently-mutable number. An item
 * at or below its reorder threshold is flagged so shortages are visible. */
export function InventoryPage() {
  const organization = useCurrentOrganization();
  const { sites } = useAllSites(organization?.id);
  const [items, setItems] = useState<InventoryItem[]>([]);
  const [balances, setBalances] = useState<Record<string, number>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sku, setSku] = useState('');
  const [name, setName] = useState('');
  const [category, setCategory] = useState('');
  const [reorderAt, setReorderAt] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [movementQuantities, setMovementQuantities] = useState<Record<string, string>>({});
  const [chosenSiteId, setChosenSiteId] = useState('');

  const selectedSiteId = chosenSiteId || sites[0]?.id;

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      const [loaded, levels] = await Promise.all([
        inventoryService.getItems(organization.id),
        selectedSiteId ? inventoryService.getBalances(selectedSiteId) : Promise.resolve({} as Record<string, number>),
      ]);
      setItems(loaded);
      setBalances(levels);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load inventory.'));
    } finally {
      setIsLoading(false);
    }
  }, [organization, selectedSiteId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!organization) return <NoActiveOrganizationNotice resource="inventory" />;

  const handleCreate = async () => {
    if (!sku.trim() || !name.trim() || !category.trim()) return;
    const threshold = reorderAt.trim() === '' ? undefined : Number(reorderAt);
    if (threshold !== undefined && (!Number.isFinite(threshold) || threshold < 0)) {
      setError('The reorder level must be zero or more.');
      return;
    }
    setIsSubmitting(true);
    setError(null);
    try {
      await inventoryService.createItem({ tenantId: organization.id, sku: sku.trim(), name: name.trim(), category: category.trim(), reorderThreshold: threshold });
      setSku('');
      setName('');
      setCategory('');
      setReorderAt('');
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the inventory item.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleMovement = async (itemId: string, movementType: 'receipt' | 'issue') => {
    const quantity = Number(movementQuantities[itemId]);
    if (!selectedSiteId) return;
    if (!Number.isFinite(quantity) || quantity <= 0) {
      setError('Enter a quantity greater than zero.');
      return;
    }
    setError(null);
    try {
      await inventoryService.recordMovement({ itemId, siteId: selectedSiteId, movementType, quantity, reference: movementType === 'receipt' ? 'manual receipt' : 'manual issue' });
      setMovementQuantities((prev) => ({ ...prev, [itemId]: '' }));
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, movementType === 'receipt' ? 'Failed to record the receipt.' : 'Failed to record the issue.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Inventory" description="Operational stock — consumables, supplies and site materials." />

      <ErrorAlert message={error} />

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <p className="text-sm font-medium text-content-primary">Add an item</p>
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <TextField label="SKU" placeholder="SKU-001" value={sku} onChange={(event) => setSku(event.target.value)} />
          <TextField label="Name" placeholder="Disinfectant 5L" value={name} onChange={(event) => setName(event.target.value)} />
          <TextField label="Category" placeholder="consumables" value={category} onChange={(event) => setCategory(event.target.value)} />
          <TextField label="Reorder level" type="number" min={0} placeholder="optional" value={reorderAt} onChange={(event) => setReorderAt(event.target.value)} />
          <Button onClick={() => void handleCreate()} isLoading={isSubmitting} disabled={!sku.trim() || !name.trim() || !category.trim()}>
            Add
          </Button>
        </div>
      </div>

      <div className="mt-4">
        <label htmlFor="inventory-site" className="mb-1.5 block text-sm font-medium text-content-primary">
          Site
        </label>
        <select
          id="inventory-site"
          value={selectedSiteId ?? ''}
          onChange={(event) => setChosenSiteId(event.target.value)}
          className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary sm:w-80"
        >
          {sites.length === 0 && <option value="">No sites</option>}
          {sites.map((site) => (
            <option key={site.id} value={site.id}>
              {site.name}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : items.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No inventory items yet.</p>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-border text-xs uppercase text-content-secondary">
                <th className="px-3 py-2">Item</th>
                <th className="px-3 py-2">Balance{selectedSiteId ? '' : ' (no site)'}</th>
                <th className="px-3 py-2 text-right">Movement</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => {
                const balance = selectedSiteId ? (balances[item.id] ?? 0) : null;
                const isLow = balance !== null && item.reorderThreshold !== null && balance <= item.reorderThreshold;
                return (
                  <tr key={item.id} className="border-b border-border last:border-0">
                    <td className="px-3 py-2.5">{item.sku} — {item.name}</td>
                    <td className="px-3 py-2.5">
                      <span>{balance ?? '—'} {item.unit}</span>
                      {isLow && (
                        <span className="ml-2 align-middle">
                          <StatusBadge label="Low stock" tone="warning" />
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-2.5 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <input
                          type="number"
                          min={0}
                          placeholder="qty"
                          value={movementQuantities[item.id] ?? ''}
                          onChange={(event) => setMovementQuantities((prev) => ({ ...prev, [item.id]: event.target.value }))}
                          className="focus-ring h-9 w-20 rounded-lg border border-border-strong bg-surface-raised px-2 text-sm"
                          aria-label={`Quantity for ${item.name}`}
                        />
                        <Button variant="ghost" onClick={() => void handleMovement(item.id, 'receipt')} disabled={!selectedSiteId}>Receive</Button>
                        <Button variant="ghost" onClick={() => void handleMovement(item.id, 'issue')} disabled={!selectedSiteId}>Issue</Button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </PageContainer>
  );
}
