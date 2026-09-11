import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { regionService } from '@/features/orgStructure/services/regionService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { regionSchema, regionDefaultValues, type RegionFormValues } from '@/features/orgStructure/schemas/regionSchema';
import type { Region } from '@/features/orgStructure/types/orgStructure.types';

export interface RegionFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  region?: Region | null;
  onSaved: (region: Region) => void;
}

export function RegionFormModal({ isOpen, onClose, tenantId, region, onSaved }: RegionFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const isEditing = Boolean(region);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<RegionFormValues>({ resolver: zodResolver(regionSchema), defaultValues: regionDefaultValues });

  useEffect(() => {
    if (!isOpen) return;
    reset(region ? { name: region.name, code: region.code ?? '' } : regionDefaultValues);
    setSubmitError(null);
  }, [isOpen, region, reset]);

  const onValid = async (values: RegionFormValues) => {
    setSubmitError(null);
    try {
      const payload = { name: values.name, code: values.code?.trim() || null };
      const saved = region
        ? await regionService.updateRegion(region.id, payload)
        : await regionService.createRegion(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save region.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit region' : 'Add region'}
      footer={
        <Button type="submit" form="region-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="region-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField label="Name" required placeholder="Gauteng" error={errors.name?.message} {...register('name')} />
        <TextField label="Code" placeholder="GP" error={errors.code?.message} {...register('code')} />
      </form>
    </Modal>
  );
}
