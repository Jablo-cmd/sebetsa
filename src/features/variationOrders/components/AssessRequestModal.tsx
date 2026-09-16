import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { variationOrderService } from '@/features/variationOrders/services/variationOrderService';
import type { ServiceRequest } from '@/features/variationOrders/types/variationOrder.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

interface AssessRequestModalProps {
  isOpen: boolean;
  onClose: () => void;
  request: ServiceRequest | null;
  onAssessed: (variationId: string) => void;
}

/** Converts a REQUESTED service request into a real variation_orders row — the request needs a contract + site first (assess_service_request()'s own server-side check). */
export function AssessRequestModal({ isOpen, onClose, request, onAssessed }: AssessRequestModalProps) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [reason, setReason] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!request) return null;

  const handleSubmit = async () => {
    if (!title.trim()) return;
    setIsSaving(true);
    setError(null);
    try {
      const variation = await variationOrderService.assessServiceRequest(request.id, title.trim(), description.trim() || undefined, reason.trim() || undefined);
      setTitle('');
      setDescription('');
      setReason('');
      onAssessed(variation.id);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to assess this request. It needs a contract and site linked before it can become a variation.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Assess service request">
      <div className="flex flex-col gap-4">
        <p className="rounded-lg border border-border bg-surface-sunken px-3 py-2 text-sm text-content-secondary">{request.description}</p>
        <ErrorAlert message={error} />
        <TextField label="Variation title" placeholder="Additional deep clean — reception" value={title} onChange={(event) => setTitle(event.target.value)} />
        <TextField label="Description" placeholder="Details of the work" value={description} onChange={(event) => setDescription(event.target.value)} />
        <TextField label="Reason" placeholder="Why this is billable outside the contract's existing scope" value={reason} onChange={(event) => setReason(event.target.value)} />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" onClick={() => void handleSubmit()} isLoading={isSaving} disabled={!title.trim()}>
            Create variation
          </Button>
        </div>
      </div>
    </Modal>
  );
}
