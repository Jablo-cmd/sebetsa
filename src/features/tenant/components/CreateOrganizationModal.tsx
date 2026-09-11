import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useTenant } from '@/features/tenant/context/tenantContext';
import { getDbErrorMessage } from '@/lib/dbErrors';
import {
  organizationCreateSchema,
  organizationCreateDefaultValues,
  type OrganizationCreateFormValues,
} from '@/features/tenant/schemas/organizationCreateSchema';
import type { Organization } from '@/types/organization.types';

export interface CreateOrganizationModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated: (organization: Organization) => void;
}

/** Onboarding is create-only — full profile details are edited afterwards on the Organization Profile page, once the new organization is the active tenant. */
export function CreateOrganizationModal({ isOpen, onClose, onCreated }: CreateOrganizationModalProps) {
  const { createOrganization, switchTenant } = useTenant();
  const [submitError, setSubmitError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<OrganizationCreateFormValues>({
    resolver: zodResolver(organizationCreateSchema),
    defaultValues: organizationCreateDefaultValues,
  });

  useEffect(() => {
    if (!isOpen) return;
    reset(organizationCreateDefaultValues);
    setSubmitError(null);
  }, [isOpen, reset]);

  const onValid = async (values: OrganizationCreateFormValues) => {
    setSubmitError(null);
    try {
      const organization = await createOrganization({
        name: values.name,
        industry: values.industry?.trim() || null,
        status: values.status,
      });
      await switchTenant(organization.id);
      onCreated(organization);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to create organization.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Create organization"
      footer={
        <Button type="submit" form="create-organization-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Creating…' : 'Create organization'}
        </Button>
      }
    >
      <form
        noValidate
        id="create-organization-form"
        onSubmit={handleSubmit(onValid)}
        className="flex flex-col gap-4"
      >
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField
          label="Organization name"
          required
          placeholder="Servest"
          error={errors.name?.message}
          {...register('name')}
        />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField
            label="Industry"
            placeholder="Facilities Management"
            error={errors.industry?.message}
            {...register('industry')}
          />

          <div>
            <label
              htmlFor="create-organization-status"
              className="mb-1.5 block text-sm font-medium text-content-primary"
            >
              Status
            </label>
            <select
              id="create-organization-status"
              className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('status')}
            >
              <option value="active">Active</option>
              <option value="pending">Pending</option>
              <option value="inactive">Inactive</option>
              <option value="suspended">Suspended</option>
            </select>
          </div>
        </div>
      </form>
    </Modal>
  );
}
