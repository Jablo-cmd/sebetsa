import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { siteService } from '@/features/orgStructure/services/siteService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { siteSchema, siteDefaultValues, type SiteFormValues } from '@/features/orgStructure/schemas/siteSchema';
import type { Site, Client, Region } from '@/features/orgStructure/types/orgStructure.types';

export interface SiteFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  site?: Site | null;
  clients: Client[];
  regions: Region[];
  onSaved: (site: Site) => void;
}

export function SiteFormModal({ isOpen, onClose, tenantId, site, clients, regions, onSaved }: SiteFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const isEditing = Boolean(site);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<SiteFormValues>({ resolver: zodResolver(siteSchema), defaultValues: siteDefaultValues });

  useEffect(() => {
    if (!isOpen) return;
    reset(
      site
        ? {
            name: site.name,
            clientId: site.clientId,
            regionId: site.regionId ?? '',
            address: site.address ?? '',
            siteType: site.siteType ?? '',
          }
        : siteDefaultValues,
    );
    setSubmitError(null);
  }, [isOpen, site, reset]);

  const onValid = async (values: SiteFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        name: values.name,
        clientId: values.clientId,
        regionId: values.regionId?.trim() || null,
        address: values.address?.trim() || null,
        siteType: values.siteType?.trim() || null,
      };
      const saved = site
        ? await siteService.updateSite(site.id, payload)
        : await siteService.createSite(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save site.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit site' : 'Add site'}
      footer={
        <Button type="submit" form="site-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="site-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField label="Site name" required placeholder="Sandton Mall" error={errors.name?.message} {...register('name')} />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="site-client" className="mb-1.5 block text-sm font-medium text-content-primary">
              Client <span className="text-danger-600">*</span>
            </label>
            <select
              id="site-client"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('clientId')}
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
          <div>
            <label htmlFor="site-region" className="mb-1.5 block text-sm font-medium text-content-primary">
              Region
            </label>
            <select
              id="site-region"
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
        </div>

        <TextField label="Address" error={errors.address?.message} {...register('address')} />
        <TextField
          label="Site type"
          placeholder="Shopping centre"
          error={errors.siteType?.message}
          {...register('siteType')}
        />
      </form>
    </Modal>
  );
}
