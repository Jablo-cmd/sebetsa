import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { billingService } from '@/features/billing/services/billingService';
import type { Client } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

interface CreateInvoiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  clients: Client[];
  onCreated: (invoiceId: string) => void;
}

/** The manual-invoice path — for ad hoc billing outside the recurring contract-billing / variation-invoicing flows. */
export function CreateInvoiceModal({ isOpen, onClose, clients, onCreated }: CreateInvoiceModalProps) {
  const [clientId, setClientId] = useState('');
  const [notes, setNotes] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async () => {
    if (!clientId) return;
    setIsSaving(true);
    setError(null);
    try {
      const invoice = await billingService.createDraftInvoice({ clientId, notes: notes.trim() || undefined });
      setClientId('');
      setNotes('');
      onCreated(invoice.id);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create a draft invoice.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create draft invoice">
      <div className="flex flex-col gap-4">
        <ErrorAlert message={error} />
        <label className="flex flex-col gap-1 text-sm">
          Client
          <select value={clientId} onChange={(event) => setClientId(event.target.value)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
            <option value="">Select a client…</option>
            {clients.map((client) => (
              <option key={client.id} value={client.id}>
                {client.name}
              </option>
            ))}
          </select>
        </label>
        <TextField label="Notes" placeholder="Optional" value={notes} onChange={(event) => setNotes(event.target.value)} />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" onClick={() => void handleSubmit()} isLoading={isSaving} disabled={!clientId}>
            Create draft
          </Button>
        </div>
      </div>
    </Modal>
  );
}
