import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { siteSurveyService } from '@/features/siteSurveys/services/siteSurveyService';
import type { SiteSurvey } from '@/features/siteSurveys/types/siteSurvey.types';
import type { Client } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface SiteSurveyFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  clients: Client[];
  onSaved: (survey: SiteSurvey) => void;
}

/** Quick-capture start: just enough to begin a survey from a phone on-site. Every other field is filled in progressively on the detail page. */
export function SiteSurveyFormModal({ isOpen, onClose, tenantId, clients, onSaved }: SiteSurveyFormModalProps) {
  const [clientId, setClientId] = useState('');
  const [prospectiveSiteName, setProspectiveSiteName] = useState('');
  const [address, setAddress] = useState('');
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!isOpen) return;
    setClientId('');
    setProspectiveSiteName('');
    setAddress('');
    setSubmitError(null);
  }, [isOpen]);

  const handleSubmit = async () => {
    if (!clientId || !prospectiveSiteName.trim()) return;
    setIsSubmitting(true);
    setSubmitError(null);
    try {
      const survey = await siteSurveyService.createSurvey(tenantId, {
        clientId,
        prospectiveSiteName: prospectiveSiteName.trim(),
        address: address.trim() || null,
      });
      onSaved(survey);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to start the site survey.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Start site survey"
      footer={
        <Button onClick={() => void handleSubmit()} isLoading={isSubmitting} disabled={!clientId || !prospectiveSiteName.trim()}>
          {isSubmitting ? 'Starting…' : 'Start survey'}
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
          <label htmlFor="survey-client" className="mb-1.5 block text-sm font-medium text-content-primary">
            Client / prospect <span className="text-danger-600">*</span>
          </label>
          <select
            id="survey-client"
            value={clientId}
            onChange={(event) => setClientId(event.target.value)}
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

        <TextField label="Site name" required placeholder="ABC Corporate Park" value={prospectiveSiteName} onChange={(event) => setProspectiveSiteName(event.target.value)} />
        <TextField label="Address" placeholder="1 Main Road, Johannesburg" value={address} onChange={(event) => setAddress(event.target.value)} />
      </div>
    </Modal>
  );
}
