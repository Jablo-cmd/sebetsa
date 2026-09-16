import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { contractService } from '@/features/orgStructure/services/contractService';
import type {
  Contract,
  ContractBillingFrequency,
  ContractPartyResponsibility,
  UpdateContractCommercialTermsInput,
} from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const BILLING_FREQUENCY_OPTIONS: { value: ContractBillingFrequency; label: string }[] = [
  { value: 'weekly', label: 'Weekly' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'annually', label: 'Annually' },
  { value: 'once_off', label: 'Once-off' },
];

const RESPONSIBILITY_OPTIONS: { value: ContractPartyResponsibility; label: string }[] = [
  { value: 'contractor', label: 'Contractor' },
  { value: 'client', label: 'Client' },
  { value: 'shared', label: 'Shared' },
];

const RESPONSIBILITY_LABEL: Record<ContractPartyResponsibility, string> = {
  contractor: 'Contractor',
  client: 'Client',
  shared: 'Shared',
};

const BILLING_FREQUENCY_LABEL: Record<ContractBillingFrequency, string> = {
  weekly: 'Weekly',
  monthly: 'Monthly',
  quarterly: 'Quarterly',
  annually: 'Annually',
  once_off: 'Once-off',
};

function formatCurrency(value: number | null): string {
  if (value === null) return '—';
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

export interface CommercialTermsSectionProps {
  contract: Contract;
  canManage: boolean;
  onSaved: () => Promise<void>;
}

interface FormState {
  contractValue: string;
  recurringValue: string;
  billingFrequency: ContractBillingFrequency | '';
  paymentTermsDays: string;
  renewalDate: string;
  autoRenew: boolean;
  escalationPercentage: string;
  escalationNotes: string;
  serviceFrequency: string;
  consumablesResponsibility: ContractPartyResponsibility | '';
  equipmentResponsibility: ContractPartyResponsibility | '';
  labourNotes: string;
  notes: string;
}

function toFormState(contract: Contract): FormState {
  return {
    contractValue: contract.contractValue?.toString() ?? '',
    recurringValue: contract.recurringValue?.toString() ?? '',
    billingFrequency: contract.billingFrequency ?? '',
    paymentTermsDays: contract.paymentTermsDays?.toString() ?? '',
    renewalDate: contract.renewalDate ?? '',
    autoRenew: contract.autoRenew,
    escalationPercentage: contract.escalationPercentage?.toString() ?? '',
    escalationNotes: contract.escalationNotes ?? '',
    serviceFrequency: contract.serviceFrequency ?? '',
    consumablesResponsibility: contract.consumablesResponsibility ?? '',
    equipmentResponsibility: contract.equipmentResponsibility ?? '',
    labourNotes: contract.labourNotes ?? '',
    notes: contract.notes ?? '',
  };
}

/** Commercial contract terms — value, billing, renewal, escalation, responsibility split. Every save is auto-versioned by the DB (contracts_snapshot_version_trigger), never a silent overwrite. */
export function CommercialTermsSection({ contract, canManage, onSaved }: CommercialTermsSectionProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState<FormState>(() => toFormState(contract));
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const startEditing = () => {
    setForm(toFormState(contract));
    setError(null);
    setIsEditing(true);
  };

  const handleSave = async () => {
    setIsSaving(true);
    setError(null);
    try {
      const payload: UpdateContractCommercialTermsInput = {
        contractValue: form.contractValue.trim() === '' ? null : Number(form.contractValue),
        recurringValue: form.recurringValue.trim() === '' ? null : Number(form.recurringValue),
        billingFrequency: form.billingFrequency === '' ? null : form.billingFrequency,
        paymentTermsDays: form.paymentTermsDays.trim() === '' ? null : Number(form.paymentTermsDays),
        renewalDate: form.renewalDate.trim() === '' ? null : form.renewalDate,
        autoRenew: form.autoRenew,
        escalationPercentage: form.escalationPercentage.trim() === '' ? null : Number(form.escalationPercentage),
        escalationNotes: form.escalationNotes.trim() === '' ? null : form.escalationNotes.trim(),
        serviceFrequency: form.serviceFrequency.trim() === '' ? null : form.serviceFrequency.trim(),
        consumablesResponsibility: form.consumablesResponsibility === '' ? null : form.consumablesResponsibility,
        equipmentResponsibility: form.equipmentResponsibility === '' ? null : form.equipmentResponsibility,
        labourNotes: form.labourNotes.trim() === '' ? null : form.labourNotes.trim(),
        notes: form.notes.trim() === '' ? null : form.notes.trim(),
      };
      await contractService.updateContractCommercialTerms(contract.id, payload);
      await onSaved();
      setIsEditing(false);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to save the commercial terms.'));
    } finally {
      setIsSaving(false);
    }
  };

  if (!isEditing) {
    return (
      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Commercial terms</h2>
          {canManage && (
            <Button variant="ghost" onClick={startEditing}>
              Edit
            </Button>
          )}
        </div>
        <dl className="grid grid-cols-1 gap-4 rounded-card border border-border bg-surface-raised p-4 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Contract value</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(contract.contractValue)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Recurring value</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {formatCurrency(contract.recurringValue)}
              {contract.billingFrequency ? ` / ${BILLING_FREQUENCY_LABEL[contract.billingFrequency].toLowerCase()}` : ''}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Payment terms</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.paymentTermsDays ? `Net ${contract.paymentTermsDays} days` : '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Renewal date</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {contract.renewalDate ?? '—'} {contract.autoRenew && '(auto-renew)'}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Escalation</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.escalationPercentage !== null ? `${contract.escalationPercentage}%` : '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Service frequency</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.serviceFrequency ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Consumables responsibility</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {contract.consumablesResponsibility ? RESPONSIBILITY_LABEL[contract.consumablesResponsibility] : '—'}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Equipment responsibility</dt>
            <dd className="mt-1 text-sm text-content-primary">
              {contract.equipmentResponsibility ? RESPONSIBILITY_LABEL[contract.equipmentResponsibility] : '—'}
            </dd>
          </div>
          {contract.labourNotes && (
            <div className="sm:col-span-2">
              <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Labour notes</dt>
              <dd className="mt-1 whitespace-pre-wrap text-sm text-content-primary">{contract.labourNotes}</dd>
            </div>
          )}
          {contract.notes && (
            <div className="sm:col-span-2">
              <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Notes</dt>
              <dd className="mt-1 whitespace-pre-wrap text-sm text-content-primary">{contract.notes}</dd>
            </div>
          )}
        </dl>
      </section>
    );
  }

  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-base font-semibold text-content-primary">Edit commercial terms</h2>
      <ErrorAlert message={error} />
      <div className="grid grid-cols-1 gap-4 rounded-card border border-border bg-surface-raised p-4 sm:grid-cols-2">
        <TextField
          label="Contract value (ZAR)"
          type="number"
          min={0}
          value={form.contractValue}
          onChange={(event) => setForm((prev) => ({ ...prev, contractValue: event.target.value }))}
        />
        <TextField
          label="Recurring value (ZAR)"
          type="number"
          min={0}
          value={form.recurringValue}
          onChange={(event) => setForm((prev) => ({ ...prev, recurringValue: event.target.value }))}
        />
        <label className="flex flex-col gap-1.5 text-sm">
          <span className="font-medium text-content-primary">Billing frequency</span>
          <select
            value={form.billingFrequency}
            onChange={(event) => setForm((prev) => ({ ...prev, billingFrequency: event.target.value as ContractBillingFrequency | '' }))}
            className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-content-primary"
          >
            <option value="">Not set</option>
            {BILLING_FREQUENCY_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <TextField
          label="Payment terms (days)"
          type="number"
          min={1}
          value={form.paymentTermsDays}
          onChange={(event) => setForm((prev) => ({ ...prev, paymentTermsDays: event.target.value }))}
        />
        <TextField
          label="Renewal date"
          type="date"
          value={form.renewalDate}
          onChange={(event) => setForm((prev) => ({ ...prev, renewalDate: event.target.value }))}
        />
        <label className="mt-7 flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.autoRenew}
            onChange={(event) => setForm((prev) => ({ ...prev, autoRenew: event.target.checked }))}
            className="focus-ring h-4 w-4 rounded border-border-strong"
          />
          Auto-renew
        </label>
        <TextField
          label="Escalation (%)"
          type="number"
          min={0}
          max={100}
          value={form.escalationPercentage}
          onChange={(event) => setForm((prev) => ({ ...prev, escalationPercentage: event.target.value }))}
        />
        <TextField
          label="Service frequency"
          placeholder="5x per week"
          value={form.serviceFrequency}
          onChange={(event) => setForm((prev) => ({ ...prev, serviceFrequency: event.target.value }))}
        />
        <label className="flex flex-col gap-1.5 text-sm">
          <span className="font-medium text-content-primary">Consumables responsibility</span>
          <select
            value={form.consumablesResponsibility}
            onChange={(event) =>
              setForm((prev) => ({ ...prev, consumablesResponsibility: event.target.value as ContractPartyResponsibility | '' }))
            }
            className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-content-primary"
          >
            <option value="">Not set</option>
            {RESPONSIBILITY_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1.5 text-sm">
          <span className="font-medium text-content-primary">Equipment responsibility</span>
          <select
            value={form.equipmentResponsibility}
            onChange={(event) =>
              setForm((prev) => ({ ...prev, equipmentResponsibility: event.target.value as ContractPartyResponsibility | '' }))
            }
            className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3.5 text-content-primary"
          >
            <option value="">Not set</option>
            {RESPONSIBILITY_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1.5 text-sm sm:col-span-2">
          <span className="font-medium text-content-primary">Escalation notes</span>
          <textarea
            rows={2}
            value={form.escalationNotes}
            onChange={(event) => setForm((prev) => ({ ...prev, escalationNotes: event.target.value }))}
            className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary"
          />
        </label>
        <label className="flex flex-col gap-1.5 text-sm sm:col-span-2">
          <span className="font-medium text-content-primary">Labour notes</span>
          <textarea
            rows={2}
            value={form.labourNotes}
            onChange={(event) => setForm((prev) => ({ ...prev, labourNotes: event.target.value }))}
            className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary"
          />
        </label>
        <label className="flex flex-col gap-1.5 text-sm sm:col-span-2">
          <span className="font-medium text-content-primary">Notes</span>
          <textarea
            rows={2}
            value={form.notes}
            onChange={(event) => setForm((prev) => ({ ...prev, notes: event.target.value }))}
            className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary"
          />
        </label>
      </div>
      <div className="flex gap-2">
        <Button onClick={() => void handleSave()} isLoading={isSaving}>
          Save terms
        </Button>
        <Button variant="ghost" onClick={() => setIsEditing(false)} disabled={isSaving}>
          Cancel
        </Button>
      </div>
    </section>
  );
}
