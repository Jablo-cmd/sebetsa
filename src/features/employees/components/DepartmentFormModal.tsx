import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { departmentService } from '@/features/employees/services/departmentService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import {
  departmentSchema,
  departmentDefaultValues,
  type DepartmentFormValues,
} from '@/features/employees/schemas/departmentSchema';
import type { Department } from '@/features/employees/types/employee.types';

export interface DepartmentFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  department?: Department | null;
  onSaved: () => void;
}

export function DepartmentFormModal({ isOpen, onClose, tenantId, department, onSaved }: DepartmentFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const isEditing = Boolean(department);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<DepartmentFormValues>({ resolver: zodResolver(departmentSchema), defaultValues: departmentDefaultValues });

  useEffect(() => {
    if (!isOpen) return;
    reset(department ? { name: department.name } : departmentDefaultValues);
    setSubmitError(null);
  }, [isOpen, department, reset]);

  const onValid = async (values: DepartmentFormValues) => {
    setSubmitError(null);
    try {
      if (department) {
        await departmentService.updateDepartment(department.id, values);
      } else {
        await departmentService.createDepartment(tenantId, values);
      }
      onSaved();
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save department.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit department' : 'Add department'}
      footer={
        <Button type="submit" form="department-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="department-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField label="Name" required placeholder="Finance" error={errors.name?.message} {...register('name')} />
      </form>
    </Modal>
  );
}
