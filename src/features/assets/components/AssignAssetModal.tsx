import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { employeeService } from '@/features/employees/services/employeeService';
import { assetService } from '@/features/assets/services/assetService';
import type { Asset } from '@/features/assets/types/assets.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

interface Candidate {
  id: string;
  firstName: string;
  lastName: string;
}

export interface AssignAssetModalProps {
  isOpen: boolean;
  onClose: () => void;
  asset: Asset | null;
  tenantId: string;
  onAssigned: () => void;
}

/** Hands an available asset to an employee (custodian). The assign_asset RPC records the assignment, the custodian and an audit entry. */
export function AssignAssetModal({ isOpen, onClose, asset, tenantId, onAssigned }: AssignAssetModalProps) {
  const [search, setSearch] = useState('');
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<Candidate | null>(null);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!isOpen) return;
    setSearch('');
    setCandidates([]);
    setSelected(null);
    setReason('');
    setError(null);
  }, [isOpen]);

  if (!asset) return null;

  const handleSearch = async (query: string) => {
    setSearch(query);
    try {
      setCandidates(await employeeService.searchEmployeeCandidates(tenantId, query));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to search employees.'));
    }
  };

  const handleAssign = async () => {
    if (!selected) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await assetService.assignAsset(asset.id, selected.id, reason.trim() || undefined);
      onAssigned();
      onClose();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to assign the asset.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Assign ${asset.name}`}
      footer={
        <Button type="button" onClick={() => void handleAssign()} isLoading={isSubmitting} disabled={!selected}>
          Assign asset
        </Button>
      }
    >
      <div className="flex flex-col gap-3">
        {error && (
          <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">
            {error}
          </div>
        )}
        <TextField
          label="Employee"
          placeholder="Search by name…"
          hint={selected ? `Selected: ${selected.firstName} ${selected.lastName}` : undefined}
          value={search}
          onChange={(event) => void handleSearch(event.target.value)}
        />
        <div className="flex max-h-32 flex-col gap-1 overflow-y-auto">
          {candidates.map((candidate) => (
            <button
              key={candidate.id}
              type="button"
              onClick={() => setSelected(candidate)}
              className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                selected?.id === candidate.id ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10' : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
              }`}
            >
              {candidate.firstName} {candidate.lastName}
            </button>
          ))}
        </div>
        <TextField label="Reason (optional)" placeholder="e.g. daily use at Tower A" value={reason} onChange={(event) => setReason(event.target.value)} />
      </div>
    </Modal>
  );
}
