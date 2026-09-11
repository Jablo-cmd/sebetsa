import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { shiftDefinitionService } from '@/features/scheduling/services/shiftDefinitionService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import {
  shiftDefinitionSchema,
  shiftDefinitionDefaultValues,
  type ShiftDefinitionFormValues,
} from '@/features/scheduling/schemas/shiftDefinitionSchema';
import type { ShiftDefinition } from '@/features/scheduling/types/scheduling.types';

export interface ShiftDefinitionFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  shiftDefinition?: ShiftDefinition | null;
  onSaved: (definition: ShiftDefinition) => void;
}

export function ShiftDefinitionFormModal({ isOpen, onClose, tenantId, shiftDefinition, onSaved }: ShiftDefinitionFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const isEditing = Boolean(shiftDefinition);

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<ShiftDefinitionFormValues>({
    resolver: zodResolver(shiftDefinitionSchema),
    defaultValues: shiftDefinitionDefaultValues,
  });

  useEffect(() => {
    if (!isOpen) return;
    reset(
      shiftDefinition
        ? {
            name: shiftDefinition.name,
            startTime: shiftDefinition.startTime.slice(0, 5),
            endTime: shiftDefinition.endTime.slice(0, 5),
            isOvernight: shiftDefinition.isOvernight,
            breakMinutes: shiftDefinition.breakMinutes,
          }
        : shiftDefinitionDefaultValues,
    );
    setSubmitError(null);
  }, [isOpen, shiftDefinition, reset]);

  const onValid = async (values: ShiftDefinitionFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        name: values.name,
        startTime: values.startTime,
        endTime: values.endTime,
        isOvernight: values.isOvernight,
        breakMinutes: values.breakMinutes,
      };
      const saved = shiftDefinition
        ? await shiftDefinitionService.updateShiftDefinition(shiftDefinition.id, payload)
        : await shiftDefinitionService.createShiftDefinition(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save shift definition.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit shift definition' : 'Add shift definition'}
      footer={
        <Button type="submit" form="shift-definition-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="shift-definition-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField label="Name" required placeholder="Day Shift" error={errors.name?.message} {...register('name')} />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Start time" type="time" required error={errors.startTime?.message} {...register('startTime')} />
          <TextField label="End time" type="time" required error={errors.endTime?.message} {...register('endTime')} />
        </div>

        <TextField
          label="Break (minutes)"
          type="number"
          min={0}
          error={errors.breakMinutes?.message}
          {...register('breakMinutes')}
        />

        <label className="flex items-center gap-2 text-sm font-medium text-content-primary">
          <input type="checkbox" className="focus-ring h-4 w-4 rounded border-border-strong" {...register('isOvernight')} />
          Overnight shift (ends the day after it starts)
        </label>
      </form>
    </Modal>
  );
}
