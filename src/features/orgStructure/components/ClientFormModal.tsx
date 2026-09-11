import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { clientService } from '@/features/orgStructure/services/clientService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { clientSchema, clientDefaultValues, type ClientFormValues } from '@/features/orgStructure/schemas/clientSchema';
import type { Client, Region } from '@/features/orgStructure/types/orgStructure.types';

export interface ClientFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  client?: Client | null;
  regions: Region[];
  onSaved: (client: Client) => void;
}

export function ClientFormModal({ isOpen, onClose, tenantId, client, regions, onSaved }: ClientFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const isEditing = Boolean(client);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<ClientFormValues>({ resolver: zodResolver(clientSchema), defaultValues: clientDefaultValues });

  useEffect(() => {
    if (!isOpen) return;
    reset(
      client
        ? {
            name: client.name,
            regionId: client.regionId ?? '',
            industry: client.industry ?? '',
            primaryContactName: client.primaryContactName ?? '',
            primaryContactEmail: client.primaryContactEmail ?? '',
            primaryContactPhone: client.primaryContactPhone ?? '',
          }
        : clientDefaultValues,
    );
    setSubmitError(null);
  }, [isOpen, client, reset]);

  const onValid = async (values: ClientFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        name: values.name,
        regionId: values.regionId?.trim() || null,
        industry: values.industry?.trim() || null,
        primaryContactName: values.primaryContactName?.trim() || null,
        primaryContactEmail: values.primaryContactEmail?.trim() || null,
        primaryContactPhone: values.primaryContactPhone?.trim() || null,
      };
      const saved = client
        ? await clientService.updateClient(client.id, payload)
        : await clientService.createClient(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save client.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit client' : 'Add client'}
      footer={
        <Button type="submit" form="client-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="client-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField
          label="Client name"
          required
          placeholder="ACME Property Group"
          error={errors.name?.message}
          {...register('name')}
        />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="client-region" className="mb-1.5 block text-sm font-medium text-content-primary">
              Region
            </label>
            <select
              id="client-region"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('regionId')}
            >
              <option value="">Unassigned</option>
              {regions.map((region) => (
                <option key={region.id} value={region.id}>
                  {region.name}
                </option>
              ))}
            </select>
          </div>
          <TextField
            label="Industry"
            placeholder="Retail Property"
            error={errors.industry?.message}
            {...register('industry')}
          />
        </div>

        <TextField
          label="Primary contact name"
          error={errors.primaryContactName?.message}
          {...register('primaryContactName')}
        />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField
            label="Contact email"
            error={errors.primaryContactEmail?.message}
            {...register('primaryContactEmail')}
          />
          <TextField
            label="Contact phone"
            error={errors.primaryContactPhone?.message}
            {...register('primaryContactPhone')}
          />
        </div>
      </form>
    </Modal>
  );
}
