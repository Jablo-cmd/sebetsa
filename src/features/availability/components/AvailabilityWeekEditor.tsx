import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import {
  availabilityWindowSchema,
  availabilityWindowDefaultValues,
  type AvailabilityWindowFormValues,
} from '@/features/availability/schemas/availabilitySchema';
import type { AvailabilityWindow } from '@/features/availability/types/availability.types';

const DAY_LABELS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export interface AvailabilityWeekEditorProps {
  windows: AvailabilityWindow[];
  canManage: boolean;
  onAdd: (values: AvailabilityWindowFormValues) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
}

export function AvailabilityWeekEditor({ windows, canManage, onAdd, onDelete }: AvailabilityWeekEditorProps) {
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<AvailabilityWindowFormValues>({
    resolver: zodResolver(availabilityWindowSchema),
    defaultValues: availabilityWindowDefaultValues,
  });

  const onValid = async (values: AvailabilityWindowFormValues) => {
    await onAdd(values);
    reset(availabilityWindowDefaultValues);
  };

  return (
    <div className="flex flex-col gap-3">
      {DAY_LABELS.map((label, dayOfWeek) => {
        const dayWindows = windows.filter((w) => w.dayOfWeek === dayOfWeek);
        return (
          <div key={label} className="flex flex-col gap-1.5 rounded-card border border-border bg-surface-raised p-3.5 sm:flex-row sm:items-center sm:justify-between">
            <span className="w-28 shrink-0 text-sm font-medium text-content-primary">{label}</span>
            {dayWindows.length === 0 ? (
              <span className="text-sm text-content-tertiary">Unavailable</span>
            ) : (
              <div className="flex flex-1 flex-wrap gap-1.5">
                {dayWindows.map((window) => (
                  <span
                    key={window.id}
                    className="inline-flex items-center gap-1.5 rounded-full border border-border-strong bg-surface-sunken px-2.5 py-1 text-xs font-medium text-content-secondary"
                  >
                    {window.startTime.slice(0, 5)}–{window.endTime.slice(0, 5)}
                    {canManage && (
                      <button
                        type="button"
                        aria-label={`Remove ${label} ${window.startTime.slice(0, 5)}-${window.endTime.slice(0, 5)}`}
                        onClick={() => void onDelete(window.id)}
                        className="focus-ring rounded-full text-content-tertiary hover:text-danger-600"
                      >
                        ×
                      </button>
                    )}
                  </span>
                ))}
              </div>
            )}
          </div>
        );
      })}

      {canManage && (
        <form
          noValidate
          onSubmit={handleSubmit(onValid)}
          className="flex flex-col gap-3 rounded-card border border-dashed border-border-strong p-3.5 sm:flex-row sm:items-end"
        >
          <div className="flex-1">
            <label htmlFor="availability-day" className="mb-1.5 block text-sm font-medium text-content-primary">
              Add window
            </label>
            <select
              id="availability-day"
              className="focus-ring h-11 w-full rounded-md border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('dayOfWeek')}
            >
              {DAY_LABELS.map((label, index) => (
                <option key={label} value={index}>
                  {label}
                </option>
              ))}
            </select>
          </div>
          <TextField label="Start" type="time" error={errors.startTime?.message} {...register('startTime')} />
          <TextField label="End" type="time" error={errors.endTime?.message} {...register('endTime')} />
          <div className="sm:w-32">
            <Button type="submit" isLoading={isSubmitting}>
              Add
            </Button>
          </div>
        </form>
      )}
    </div>
  );
}
