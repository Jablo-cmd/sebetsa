import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { employeeService } from '@/features/employees/services/employeeService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { PROVISIONABLE_ROLES, PROVISIONABLE_ROLE_LABELS } from '@/features/employees/types/employee.types';
import type { Employee, ProvisionLoginResult } from '@/features/employees/types/employee.types';
import {
  provisionLoginSchema,
  provisionLoginDefaultValues,
  type ProvisionLoginFormValues,
} from '@/features/employees/schemas/provisionLoginSchema';

export interface ProvisionLoginModalProps {
  isOpen: boolean;
  onClose: () => void;
  employee: Employee;
  onProvisioned: () => void;
}

export function ProvisionLoginModal({ isOpen, onClose, employee, onProvisioned }: ProvisionLoginModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [result, setResult] = useState<ProvisionLoginResult | null>(null);
  const canProvision = Boolean(employee.email);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<ProvisionLoginFormValues>({
    resolver: zodResolver(provisionLoginSchema),
    defaultValues: { ...provisionLoginDefaultValues, phone: employee.phone ?? '' },
  });

  // Unlike CreateUserModal (which also shows a persistent temp-password
  // screen), this modal lives on a *detail* page: EmployeeProfilePage has a
  // page-level `if (isLoading) return <FullScreenSpinner/>`, so calling the
  // parent's refetch() immediately on success would flip isLoading back to
  // true and unmount this modal — including its `result` state — before
  // the user ever sees the password. Deferring onProvisioned() to
  // handleClose (i.e. after the user has dismissed the success screen)
  // avoids that; CreateUserModal doesn't need this because UsersPage (a
  // list page) never unmounts it on refetch.
  const handleClose = () => {
    const wasProvisioned = Boolean(result);
    setSubmitError(null);
    setResult(null);
    reset({ ...provisionLoginDefaultValues, phone: employee.phone ?? '' });
    onClose();
    if (wasProvisioned) onProvisioned();
  };

  const onValid = async (values: ProvisionLoginFormValues) => {
    setSubmitError(null);
    try {
      const provisioned = await employeeService.provisionLogin(employee.id, values.role, values.phone?.trim() || null);
      setResult(provisioned);
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to provision login.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title={result ? 'Login provisioned' : 'Provision login'}
      footer={
        result ? (
          <Button type="button" onClick={handleClose}>
            Done
          </Button>
        ) : canProvision ? (
          <Button type="submit" form="provision-login-form" isLoading={isSubmitting}>
            {isSubmitting ? 'Provisioning…' : 'Provision login'}
          </Button>
        ) : (
          <Button type="button" onClick={handleClose}>
            Close
          </Button>
        )
      }
    >
      {result ? (
        <div className="flex flex-col gap-4">
          <div
            role="status"
            className="rounded-lg border border-success-500/30 bg-success-500/10 px-3.5 py-2.5 text-sm font-medium text-success-500"
          >
            The login was created successfully.
          </div>
          <div className="rounded-lg border border-border bg-surface-sunken px-3.5 py-3 text-sm">
            <p className="text-content-secondary">
              Temporary password — share this with {employee.firstName}, it won&apos;t be shown again:
            </p>
            <p className="mt-1.5 select-all break-all font-mono text-content-primary">{result.temporaryPassword}</p>
          </div>
        </div>
      ) : !canProvision ? (
        <div
          role="alert"
          className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
        >
          {employee.firstName} has no work email on file. Add one under Edit details before provisioning a login.
        </div>
      ) : (
        <form noValidate id="provision-login-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
          {submitError && (
            <div
              role="alert"
              className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
            >
              {submitError}
            </div>
          )}

          <p className="text-sm text-content-secondary">
            Creates a login for <span className="font-medium text-content-primary">{employee.email}</span>. A
            one-time temporary password will be shown once, on this screen only.
          </p>

          <div>
            <label htmlFor="provision-login-role" className="mb-1.5 block text-sm font-medium text-content-primary">
              Role{' '}
              <span className="text-danger-600" aria-hidden="true">
                *
              </span>
            </label>
            <select
              id="provision-login-role"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('role')}
            >
              {PROVISIONABLE_ROLES.map((role) => (
                <option key={role} value={role}>
                  {PROVISIONABLE_ROLE_LABELS[role]}
                </option>
              ))}
            </select>
            {errors.role && (
              <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
                {errors.role.message}
              </p>
            )}
          </div>

          <TextField label="Phone" type="tel" error={errors.phone?.message} {...register('phone')} />
        </form>
      )}
    </Modal>
  );
}
