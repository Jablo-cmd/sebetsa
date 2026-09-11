import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import {
  availabilityExceptionSchema,
  availabilityExceptionDefaultValues,
  type AvailabilityExceptionFormValues,
} from '@/features/availability/schemas/availabilitySchema';
import type { AvailabilityException } from '@/features/availability/types/availability.types';

export interface AvailabilityExceptionsPanelProps {
  exceptions: AvailabilityException[];
  canManage: boolean;
  onAdd: (values: AvailabilityExceptionFormValues) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}

export function AvailabilityExceptionsPanel({ exceptions, canManage, onAdd, onDelete }: AvailabilityExceptionsPanelProps) {
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<AvailabilityExceptionFormValues>({
    resolver: zodResolver(availabilityExceptionSchema),
    defaultValues: availabilityExceptionDefaultValues,
  });

  const onValid = async (values: AvailabilityExceptionFormValues) => {
    await onAdd(values);
    reset(availabilityExceptionDefaultValues);
  };

  return (
    <div className="flex flex-col gap-3">
      {exceptions.length === 0 ? (
        <p className="rounded-card border border-border bg-surface-raised px-4 py-6 text-center text-sm text-content-tertiary">
          No upcoming exceptions.
        </p>
      ) : (
        <div className="flex flex-col gap-2">
          {exceptions.map((exception) => (
            <div
              key={exception.id}
              className="flex items-center justify-between rounded-card border border-border bg-surface-raised p-3.5"
            >
              <div>
                <p className="text-sm font-medium text-content-primary">
                  {new Date(`${exception.exceptionDate}T00:00:00`).toLocaleDateString('en-ZA', {
                    weekday: 'short',
                    day: '2-digit',
                    month: 'short',
                    year: 'numeric',
                  })}
                </p>
                <p className="text-sm text-content-secondary">
                  {exception.isAvailable
                    ? exception.startTime && exception.endTime
                      ? `Available ${exception.startTime.slice(0, 5)}–${exception.endTime.slice(0, 5)} only`
                      : 'Available'
                    : 'Unavailable all day'}
                  {exception.reason && ` · ${exception.reason}`}
                </p>
              </div>
              {canManage && (
                <button
                  type="button"
                  onClick={() => void onDelete(exception.id)}
                  className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50"
                >
                  Remove
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {canManage && (
        <form
          noValidate
          onSubmit={handleSubmit(onValid)}
          className="flex flex-col gap-3 rounded-card border border-dashed border-border-strong p-3.5"
        >
          <p className="text-sm font-medium text-content-primary">Add exception</p>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <TextField label="Date" type="date" required error={errors.exceptionDate?.message} {...register('exceptionDate')} />
            <div>
              <label htmlFor="exception-is-available" className="mb-1.5 block text-sm font-medium text-content-primary">
                Availability
              </label>
              <select
                id="exception-is-available"
                className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
                {...register('isAvailable', { setValueAs: (v: string) => v === 'true' })}
              >
                <option value="false">Unavailable all day</option>
                <option value="true">Available (narrower window)</option>
              </select>
            </div>
          </div>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <TextField label="Start (optional)" type="time" error={errors.startTime?.message} {...register('startTime')} />
            <TextField label="End (optional)" type="time" error={errors.endTime?.message} {...register('endTime')} />
          </div>
          <TextField label="Reason (optional)" placeholder="e.g. appointment" error={errors.reason?.message} {...register('reason')} />
          <div className="sm:w-40">
            <Button type="submit" isLoading={isSubmitting}>
              Add exception
            </Button>
          </div>
        </form>
      )}
    </div>
  );
}
