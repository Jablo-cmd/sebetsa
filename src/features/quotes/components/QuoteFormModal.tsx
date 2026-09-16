import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { quoteService } from '@/features/quotes/services/quoteService';
import type { Quote } from '@/features/quotes/types/quote.types';
import type { Client, Site } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface QuoteFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  clients: Client[];
  sites: Site[];
  onSaved: (quote: Quote) => void;
}

export function QuoteFormModal({ isOpen, onClose, tenantId, clients, sites, onSaved }: QuoteFormModalProps) {
  const [clientId, setClientId] = useState('');
  const [siteId, setSiteId] = useState('');
  const [quoteNumber, setQuoteNumber] = useState('');
  const [expiryDate, setExpiryDate] = useState('');
  const [taxRate, setTaxRate] = useState('15');
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!isOpen) return;
    setClientId('');
    setSiteId('');
    setQuoteNumber('');
    setExpiryDate('');
    setTaxRate('15');
    setSubmitError(null);
  }, [isOpen]);

  const sitesForClient = sites.filter((s) => s.clientId === clientId);

  const handleSubmit = async () => {
    if (!clientId || !quoteNumber.trim()) return;
    setIsSubmitting(true);
    setSubmitError(null);
    try {
      const quote = await quoteService.createQuote(tenantId, {
        clientId,
        siteId: siteId || null,
        quoteNumber: quoteNumber.trim(),
        expiryDate: expiryDate || null,
        taxRate: taxRate.trim() === '' ? undefined : Number(taxRate),
      });
      onSaved(quote);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to create the quote.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Add quote"
      footer={
        <Button onClick={() => void handleSubmit()} isLoading={isSubmitting} disabled={!clientId || !quoteNumber.trim()}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <div className="flex flex-col gap-4">
        {submitError && (
          <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">
            {submitError}
          </div>
        )}

        <div>
          <label htmlFor="quote-client" className="mb-1.5 block text-sm font-medium text-content-primary">
            Client <span className="text-danger-600">*</span>
          </label>
          <select
            id="quote-client"
            value={clientId}
            onChange={(event) => {
              setClientId(event.target.value);
              setSiteId('');
            }}
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
          >
            <option value="">Select a client…</option>
            {clients.map((client) => (
              <option key={client.id} value={client.id}>
                {client.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="quote-site" className="mb-1.5 block text-sm font-medium text-content-primary">
            Site (optional)
          </label>
          <select
            id="quote-site"
            value={siteId}
            onChange={(event) => setSiteId(event.target.value)}
            disabled={!clientId}
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary disabled:opacity-60"
          >
            <option value="">No specific site</option>
            {sitesForClient.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Quote number" required placeholder="QT-2026-001" value={quoteNumber} onChange={(event) => setQuoteNumber(event.target.value)} />
          <TextField label="Expiry date" type="date" value={expiryDate} onChange={(event) => setExpiryDate(event.target.value)} />
        </div>
        <TextField label="Tax rate (%)" type="number" min={0} max={100} value={taxRate} onChange={(event) => setTaxRate(event.target.value)} />
      </div>
    </Modal>
  );
}
