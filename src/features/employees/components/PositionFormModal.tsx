import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { positionService } from '@/features/employees/services/positionService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { positionSchema, positionDefaultValues, type PositionFormValues } from '@/features/employees/schemas/positionSchema';
import type { Position, Department } from '@/features/employees/types/employee.types';

export interface PositionFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  position?: Position | null;
  departments: Department[];
  onSaved: (position: Position) => void;
}

export function PositionFormModal({ isOpen, onClose, tenantId, position, departments, onSaved }: PositionFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const isEditing = Boolean(position);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<PositionFormValues>({ resolver: zodResolver(positionSchema), defaultValues: positionDefaultValues });

  useEffect(() => {
    if (!isOpen) return;
    reset(position ? { title: position.title, departmentId: position.departmentId ?? '' } : positionDefaultValues);
    setSubmitError(null);
  }, [isOpen, position, reset]);

  const onValid = async (values: PositionFormValues) => {
    setSubmitError(null);
    try {
      const payload = { title: values.title, departmentId: values.departmentId?.trim() || null };
      const saved = position
        ? await positionService.updatePosition(position.id, payload)
        : await positionService.createPosition(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save position.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit position' : 'Add position'}
      footer={
        <Button type="submit" form="position-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="position-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField label="Title" required placeholder="Site Supervisor" error={errors.title?.message} {...register('title')} />

        <div>
          <label htmlFor="position-department" className="mb-1.5 block text-sm font-medium text-content-primary">
            Department
          </label>
          <select
            id="position-department"
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
            {...register('departmentId')}
          >
            <option value="">Unassigned</option>
            {departments.map((department) => (
              <option key={department.id} value={department.id}>
                {department.name}
              </option>
            ))}
          </select>
        </div>
      </form>
    </Modal>
  );
}
