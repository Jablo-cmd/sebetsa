import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { contractService } from '@/features/orgStructure/services/contractService';
import type { ManagerCandidate } from '@/features/orgStructure/services/contractService';
import { useContractSiteIds } from '@/features/orgStructure/hooks/useContracts';
import { getDbErrorMessage } from '@/lib/dbErrors';
import {
  contractSchema,
  contractDefaultValues,
  type ContractFormValues,
} from '@/features/orgStructure/schemas/contractSchema';
import type { Contract, Client, Site } from '@/features/orgStructure/types/orgStructure.types';

export interface ContractFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  contract?: Contract | null;
  clients: Client[];
  sites: Site[];
  onSaved: (contract: Contract) => void;
}

export function ContractFormModal({ isOpen, onClose, tenantId, contract, clients, sites, onSaved }: ContractFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [managerSearch, setManagerSearch] = useState('');
  const [managerCandidates, setManagerCandidates] = useState<ManagerCandidate[]>([]);
  const [selectedManager, setSelectedManager] = useState<ManagerCandidate | null>(null);
  const isEditing = Boolean(contract);
  const { siteIds: existingSiteIds } = useContractSiteIds(contract?.id);

  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<ContractFormValues>({ resolver: zodResolver(contractSchema), defaultValues: contractDefaultValues });

  const clientId = watch('clientId');
  const responsibleManagerId = watch('responsibleManagerId');
  const siteIds = watch('siteIds');

  useEffect(() => {
    if (!isOpen) return;
    reset(
      contract
        ? {
            clientId: contract.clientId,
            contractNumber: contract.contractNumber,
            startDate: contract.startDate,
            endDate: contract.endDate ?? '',
            responsibleManagerId: contract.responsibleManagerId ?? '',
            slaNotes: contract.slaNotes ?? '',
            siteIds: existingSiteIds,
          }
        : contractDefaultValues,
    );
    setManagerSearch('');
    setSelectedManager(null);
    setSubmitError(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, contract, existingSiteIds.join(','), reset]);

  useEffect(() => {
    if (!isOpen || !contract?.responsibleManagerId) return;
    let cancelled = false;
    void contractService.searchManagerCandidates(tenantId, '').then((results) => {
      const match = results.find((r) => r.id === contract.responsibleManagerId);
      if (!cancelled && match) setSelectedManager(match);
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, tenantId, contract?.responsibleManagerId]);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    void contractService.searchManagerCandidates(tenantId, managerSearch).then((results) => {
      if (!cancelled) setManagerCandidates(results);
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, tenantId, managerSearch]);

  const sitesForClient = sites.filter((s) => s.clientId === clientId);

  const toggleSite = (siteId: string) => {
    const current = siteIds ?? [];
    setValue(
      'siteIds',
      current.includes(siteId) ? current.filter((id) => id !== siteId) : [...current, siteId],
      { shouldValidate: true },
    );
  };

  const onValid = async (values: ContractFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        clientId: values.clientId,
        contractNumber: values.contractNumber,
        startDate: values.startDate,
        endDate: values.endDate?.trim() || null,
        responsibleManagerId: values.responsibleManagerId?.trim() || null,
        slaNotes: values.slaNotes?.trim() || null,
      };
      const saved = contract
        ? await contractService.updateContract(contract.id, payload)
        : await contractService.createContract(tenantId, { ...payload, siteIds: values.siteIds });
      if (contract) {
        await contractService.setContractSites(tenantId, contract.id, values.siteIds);
      }
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save contract.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit contract' : 'Add contract'}
      footer={
        <Button type="submit" form="contract-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="contract-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="contract-client" className="mb-1.5 block text-sm font-medium text-content-primary">
              Client <span className="text-danger-600">*</span>
            </label>
            <select
              id="contract-client"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('clientId')}
              onChange={(event) => {
                setValue('clientId', event.target.value);
                setValue('siteIds', []);
              }}
            >
              <option value="">Select a client…</option>
              {clients.map((client) => (
                <option key={client.id} value={client.id}>
                  {client.name}
                </option>
              ))}
            </select>
            {errors.clientId && (
              <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
                {errors.clientId.message}
              </p>
            )}
          </div>
          <TextField
            label="Contract number"
            required
            placeholder="SRV-2026-001"
            error={errors.contractNumber?.message}
            {...register('contractNumber')}
          />
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Start date" type="date" required error={errors.startDate?.message} {...register('startDate')} />
          <TextField label="End date" type="date" error={errors.endDate?.message} {...register('endDate')} />
        </div>

        <div>
          <span className="mb-1.5 block text-sm font-medium text-content-primary">Sites covered</span>
          {!clientId ? (
            <p className="text-sm text-content-tertiary">Select a client to choose which sites this contract covers.</p>
          ) : sitesForClient.length === 0 ? (
            <p className="text-sm text-content-tertiary">This client has no sites yet.</p>
          ) : (
            <div className="flex max-h-40 flex-col gap-1 overflow-y-auto rounded-lg border border-border-strong p-2">
              {sitesForClient.map((site) => (
                <label key={site.id} className="flex items-center gap-2 rounded px-2 py-1.5 text-sm hover:bg-surface-sunken">
                  <input
                    type="checkbox"
                    checked={(siteIds ?? []).includes(site.id)}
                    onChange={() => toggleSite(site.id)}
                    className="focus-ring h-4 w-4 rounded border-border-strong"
                  />
                  {site.name}
                </label>
              ))}
            </div>
          )}
        </div>

        <div>
          <TextField
            label="Responsible manager"
            hint={selectedManager ? `Selected: ${selectedManager.firstName} ${selectedManager.lastName}` : 'Search by name…'}
            placeholder="Search by name…"
            value={managerSearch}
            onChange={(event) => setManagerSearch(event.target.value)}
          />
          <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
            <button
              type="button"
              onClick={() => {
                setValue('responsibleManagerId', '', { shouldValidate: true });
                setSelectedManager(null);
              }}
              className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                !responsibleManagerId
                  ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                  : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
              }`}
            >
              Unassigned
            </button>
            {managerCandidates.map((candidate) => (
              <button
                key={candidate.id}
                type="button"
                onClick={() => {
                  setValue('responsibleManagerId', candidate.id, { shouldValidate: true });
                  setSelectedManager(candidate);
                }}
                className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                  responsibleManagerId === candidate.id
                    ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                    : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
                }`}
              >
                {candidate.firstName} {candidate.lastName}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label htmlFor="contract-sla" className="mb-1.5 block text-sm font-medium text-content-primary">
            SLA notes
          </label>
          <textarea
            id="contract-sla"
            rows={3}
            className="focus-ring w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-sm text-content-primary"
            {...register('slaNotes')}
          />
        </div>
      </form>
    </Modal>
  );
}
