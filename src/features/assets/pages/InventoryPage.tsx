import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { inventoryService } from '@/features/assets/services/inventoryService';
import type { InventoryItem } from '@/features/assets/types/assets.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** Inventory: items + a movement ledger. Balances are always fetched fresh
 * via get_inventory_balance() (a derived aggregate), never cached in
 * component state as an independently-mutable number. */
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
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [movementQuantities, setMovementQuantities] = useState<Record<string, string>>({});

  const selectedSiteId = sites[0]?.id;

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      const loaded = await inventoryService.getItems(organization.id);
      setItems(loaded);
      if (selectedSiteId) {
        const entries = await Promise.all(loaded.map(async (item) => [item.id, await inventoryService.getBalance(item.id, selectedSiteId)] as const));
        setBalances(Object.fromEntries(entries));
      }
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
    setIsSubmitting(true);
    setError(null);
    try {
      await inventoryService.createItem({ tenantId: organization.id, sku: sku.trim(), name: name.trim(), category: category.trim() });
      setSku('');
      setName('');
      setCategory('');
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the inventory item.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleReceive = async (itemId: string) => {
    const quantity = Number(movementQuantities[itemId]);
    if (!selectedSiteId || !quantity || quantity <= 0) return;
    setError(null);
    try {
      await inventoryService.recordMovement({ itemId, siteId: selectedSiteId, movementType: 'receipt', quantity, reference: 'manual receipt' });
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to record the receipt.'));
    }
  };

  const handleIssue = async (itemId: string) => {
    const quantity = Number(movementQuantities[itemId]);
    if (!selectedSiteId || !quantity || quantity <= 0) return;
    setError(null);
    try {
      await inventoryService.recordMovement({ itemId, siteId: selectedSiteId, movementType: 'issue', quantity, reference: 'manual issue' });
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to record the issue.'));
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
          <Button onClick={() => void handleCreate()} isLoading={isSubmitting} disabled={!sku.trim() || !name.trim() || !category.trim()}>
            Add
          </Button>
        </div>
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
              {items.map((item) => (
                <tr key={item.id} className="border-b border-border last:border-0">
                  <td className="px-3 py-2.5">{item.sku} — {item.name}</td>
                  <td className="px-3 py-2.5">{selectedSiteId ? (balances[item.id] ?? '—') : '—'} {item.unit}</td>
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
                      <Button variant="ghost" onClick={() => void handleReceive(item.id)} disabled={!selectedSiteId}>Receive</Button>
                      <Button variant="ghost" onClick={() => void handleIssue(item.id)} disabled={!selectedSiteId}>Issue</Button>
                    </div>
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
