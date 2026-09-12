import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { leaveService } from '@/features/leave/services/leaveService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { retryOnNetworkError } from '@/lib/retry';
import {
  leaveRequestSchema,
  leaveRequestDefaultValues,
  type LeaveRequestFormValues,
} from '@/features/leave/schemas/leaveRequestSchema';
import { calendarDays, workingDays } from '@/features/leave/utils/duration';
import type { LeaveType, LeaveRequest } from '@/features/leave/types/leave.types';

export interface LeaveRequestFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  employeeId: string;
  leaveTypes: LeaveType[];
  onSaved: (request: LeaveRequest) => void;
}

export function LeaveRequestFormModal({ isOpen, onClose, employeeId, leaveTypes, onSaved }: LeaveRequestFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);

  const {
    register,
    handleSubmit,
    reset,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<LeaveRequestFormValues>({ resolver: zodResolver(leaveRequestSchema), defaultValues: leaveRequestDefaultValues });

  const startDate = watch('startDate');
  const endDate = watch('endDate');
  const isHalfDay = watch('isHalfDay');

  useEffect(() => {
    if (!isOpen) return;
    reset(leaveRequestDefaultValues);
    setSubmitError(null);
  }, [isOpen, reset]);

  const onValid = async (values: LeaveRequestFormValues) => {
    setSubmitError(null);
    try {
      const saved = await retryOnNetworkError(() =>
        leaveService.submitLeaveRequest({
          employeeId,
          leaveTypeId: values.leaveTypeId,
          startDate: values.startDate,
          endDate: values.endDate,
          isHalfDay: values.isHalfDay,
          halfDayPeriod: values.isHalfDay && values.halfDayPeriod ? values.halfDayPeriod : null,
          reason: values.reason?.trim() || null,
          supportingDocumentRef: values.supportingDocumentRef?.trim() || null,
        }),
      );
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to submit the leave request.'));
    }
  };

  const showDurationPreview = startDate && endDate && endDate >= startDate;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Request leave"
      footer={
        <Button type="submit" form="leave-request-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Submitting…' : 'Submit request'}
        </Button>
      }
    >
      <form noValidate id="leave-request-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <div>
          <label htmlFor="leave-type" className="mb-1.5 block text-sm font-medium text-content-primary">
            Leave type <span className="text-danger-600">*</span>
          </label>
          <select
            id="leave-type"
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
            {...register('leaveTypeId')}
          >
            <option value="">Select a leave type…</option>
            {leaveTypes.map((type) => (
              <option key={type.id} value={type.id}>
                {type.name}
              </option>
            ))}
          </select>
          {errors.leaveTypeId && (
            <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
              {errors.leaveTypeId.message}
            </p>
          )}
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Start date" type="date" required error={errors.startDate?.message} {...register('startDate')} />
          <TextField label="End date" type="date" required error={errors.endDate?.message} {...register('endDate')} />
        </div>

        <label className="flex items-center gap-2 text-sm font-medium text-content-primary">
          <input type="checkbox" className="focus-ring h-4 w-4 rounded border-border-strong" {...register('isHalfDay')} />
          Half day
        </label>

        {isHalfDay && (
          <div>
            <label htmlFor="half-day-period" className="mb-1.5 block text-sm font-medium text-content-primary">
              Which half <span className="text-danger-600">*</span>
            </label>
            <select
              id="half-day-period"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('halfDayPeriod')}
            >
              <option value="">Select…</option>
              <option value="am">Morning (AM)</option>
              <option value="pm">Afternoon (PM)</option>
            </select>
            {errors.halfDayPeriod && (
              <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
                {errors.halfDayPeriod.message}
              </p>
            )}
          </div>
        )}

        {showDurationPreview && (
          <p className="text-xs text-content-secondary">
            {calendarDays(startDate, endDate, isHalfDay)} calendar day(s) · {workingDays(startDate, endDate, isHalfDay)} working
            day(s) (Mon–Fri, excluding public holidays)
          </p>
        )}

        <TextField
          label="Reason"
          placeholder="Optional"
          error={errors.reason?.message}
          {...register('reason')}
        />
        <TextField
          label="Supporting document reference"
          placeholder="Optional — e.g. a filed medical certificate reference"
          error={errors.supportingDocumentRef?.message}
          {...register('supportingDocumentRef')}
        />
      </form>
    </Modal>
  );
}
