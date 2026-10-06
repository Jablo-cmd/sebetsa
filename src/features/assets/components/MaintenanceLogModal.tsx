import { useCallback, useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { assetService, type MaintenanceRecord } from '@/features/assets/services/assetService';
import type { Asset } from '@/features/assets/types/assets.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface MaintenanceLogModalProps {
  isOpen: boolean;
  onClose: () => void;
  asset: Asset | null;
  canRecord: boolean;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/** The asset's maintenance history, with a form to log new work. Records are append-only and audited by the database. */
export function MaintenanceLogModal({ isOpen, onClose, asset, canRecord }: MaintenanceLogModalProps) {
  const [records, setRecords] = useState<MaintenanceRecord[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [description, setDescription] = useState('');
  const [cost, setCost] = useState('');
  const [performedAt, setPerformedAt] = useState(todayIso());
  const [isSaving, setIsSaving] = useState(false);

  const load = useCallback(async () => {
    if (!asset) return;
    setIsLoading(true);
    try {
      setRecords(await assetService.getMaintenanceRecords(asset.id));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the maintenance history.'));
    } finally {
      setIsLoading(false);
    }
  }, [asset]);

  useEffect(() => {
    if (!isOpen) return;
    setError(null);
    setDescription('');
    setCost('');
    setPerformedAt(todayIso());
    void load();
  }, [isOpen, load]);

  if (!asset) return null;

  const costValue = cost.trim() === '' ? null : Number(cost);
  const costInvalid = costValue !== null && (!Number.isFinite(costValue) || costValue < 0);

  const handleSave = async () => {
    if (!description.trim() || costInvalid) return;
    setIsSaving(true);
    setError(null);
    try {
      await assetService.recordMaintenance(asset.id, description.trim(), costValue, performedAt);
      setDescription('');
      setCost('');
      await load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to record the maintenance.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Maintenance — ${asset.assetNumber}`}>
      <div className="flex flex-col gap-4">
        <ErrorAlert message={error} />
        {isLoading ? (
          <p className="text-sm text-content-secondary">Loading…</p>
        ) : records.length === 0 ? (
          <p className="text-sm text-content-tertiary">No maintenance recorded for this asset yet.</p>
        ) : (
          <ul className="flex flex-col divide-y divide-border rounded-card border border-border">
            {records.map((record) => (
              <li key={record.id} className="px-3 py-2 text-sm">
                <p className="font-medium text-content-primary">{record.description}</p>
                <p className="text-xs text-content-tertiary">
                  {record.performedAt}
                  {record.cost !== null ? ` · cost ${record.cost}` : ''}
                </p>
              </li>
            ))}
          </ul>
        )}

        {canRecord && (
          <div className="flex flex-col gap-3 border-t border-border pt-4">
            <TextField label="Work done" placeholder="Replaced drive belt" value={description} onChange={(event) => setDescription(event.target.value)} />
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <TextField label="Cost (optional)" type="number" min="0" step="0.01" value={cost} onChange={(event) => setCost(event.target.value)} error={costInvalid ? 'Enter a cost of zero or more' : undefined} />
              <TextField label="Date performed" type="date" value={performedAt} onChange={(event) => setPerformedAt(event.target.value)} />
            </div>
            <Button onClick={() => void handleSave()} isLoading={isSaving} disabled={!description.trim() || costInvalid || !performedAt}>
              Record maintenance
            </Button>
          </div>
        )}
      </div>
    </Modal>
  );
}
