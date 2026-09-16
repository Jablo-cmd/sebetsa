import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { cleaningQaService } from '@/features/cleaningQa/services/cleaningQaService';
import type { InspectionTemplate } from '@/features/cleaningQa/types/cleaningQa.types';
import type { Client } from '@/features/orgStructure/types/orgStructure.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

interface ScheduleInspectionModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  clients: Client[];
  sites: Site[];
  templates: InspectionTemplate[];
  onScheduled: (inspectionId: string) => void;
}

export function ScheduleInspectionModal({ isOpen, onClose, tenantId, clients, sites, templates, onScheduled }: ScheduleInspectionModalProps) {
  const [clientId, setClientId] = useState('');
  const [siteId, setSiteId] = useState('');
  const [templateId, setTemplateId] = useState('');
  const [scheduledAt, setScheduledAt] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const sitesForClient = sites.filter((site) => site.clientId === clientId);

  const handleSubmit = async () => {
    if (!clientId || !siteId || !templateId) return;
    setIsSaving(true);
    setError(null);
    try {
      const inspection = await cleaningQaService.scheduleInspection(tenantId, { clientId, siteId, templateId, scheduledAt: scheduledAt || undefined });
      setClientId('');
      setSiteId('');
      setTemplateId('');
      setScheduledAt('');
      onScheduled(inspection.id);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to schedule this inspection.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Schedule inspection">
      <div className="flex flex-col gap-4">
        <ErrorAlert message={error} />
        <label className="flex flex-col gap-1 text-sm">
          Client
          <select
            value={clientId}
            onChange={(event) => {
              setClientId(event.target.value);
              setSiteId('');
            }}
            className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3"
          >
            <option value="">Select a client…</option>
            {clients.map((client) => (
              <option key={client.id} value={client.id}>
                {client.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Site
          <select value={siteId} onChange={(event) => setSiteId(event.target.value)} disabled={!clientId} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
            <option value="">Select a site…</option>
            {sitesForClient.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Template
          <select value={templateId} onChange={(event) => setTemplateId(event.target.value)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
            <option value="">Select a template…</option>
            {templates.map((template) => (
              <option key={template.id} value={template.id}>
                {template.name}
              </option>
            ))}
          </select>
        </label>
        <TextField label="Scheduled for" type="datetime-local" value={scheduledAt} onChange={(event) => setScheduledAt(event.target.value)} />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button type="button" onClick={() => void handleSubmit()} isLoading={isSaving} disabled={!clientId || !siteId || !templateId}>
            Schedule
          </Button>
        </div>
      </div>
    </Modal>
  );
}
