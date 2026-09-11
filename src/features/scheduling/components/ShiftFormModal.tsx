import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { shiftService } from '@/features/scheduling/services/shiftService';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { shiftSchema, shiftDefaultValues, type ShiftFormValues } from '@/features/scheduling/schemas/shiftSchema';
import { resolveShiftTimestamps, splitTimestamp } from '@/features/scheduling/utils/shiftTime';
import type { Shift, ShiftDefinition } from '@/features/scheduling/types/scheduling.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';

export interface ShiftFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  shift?: Shift | null;
  sites: Site[];
  shiftDefinitions: ShiftDefinition[];
  /** Pre-fills the site/employee when creating from a grid cell. */
  initialSiteId?: string;
  initialEmployeeId?: string;
  initialDate?: string;
  onSaved: (shift: Shift) => void;
}

export function ShiftFormModal({
  isOpen,
  onClose,
  tenantId,
  shift,
  sites,
  shiftDefinitions,
  initialSiteId,
  initialEmployeeId,
  initialDate,
  onSaved,
}: ShiftFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [employeeSearch, setEmployeeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedEmployee, setSelectedEmployee] = useState<EmployeeCandidate | null>(null);
  const isEditing = Boolean(shift);

  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<ShiftFormValues>({ resolver: zodResolver(shiftSchema), defaultValues: shiftDefaultValues });

  const employeeId = watch('employeeId');
  const shiftDefinitionId = watch('shiftDefinitionId');

  useEffect(() => {
    if (!isOpen) return;
    if (shift) {
      const start = splitTimestamp(shift.startsAt);
      const end = splitTimestamp(shift.endsAt);
      const endsNextDay = new Date(shift.endsAt).getDate() !== new Date(shift.startsAt).getDate();
      reset({
        siteId: shift.siteId,
        employeeId: shift.employeeId,
        supervisorId: shift.supervisorId ?? '',
        shiftDefinitionId: shift.shiftDefinitionId ?? '',
        date: start.date,
        startTime: start.time,
        endTime: end.time,
        endsNextDay,
        notes: shift.notes ?? '',
      });
    } else {
      reset({
        ...shiftDefaultValues,
        siteId: initialSiteId ?? '',
        employeeId: initialEmployeeId ?? '',
        date: initialDate ?? '',
      });
    }
    setEmployeeSearch('');
    setSelectedEmployee(null);
    setSubmitError(null);
  }, [isOpen, shift, initialSiteId, initialEmployeeId, initialDate, reset]);

  useEffect(() => {
    if (!isOpen || !(shift?.employeeId ?? initialEmployeeId)) return;
    const id = shift?.employeeId ?? initialEmployeeId;
    if (!id) return;
    let cancelled = false;
    void employeeService.getEmployee(id).then((result) => {
      if (!cancelled && result) setSelectedEmployee({ id: result.id, firstName: result.firstName, lastName: result.lastName });
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, shift?.employeeId, initialEmployeeId]);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    void employeeService.searchEmployeeCandidates(tenantId, employeeSearch).then((results) => {
      if (!cancelled) setCandidates(results);
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, tenantId, employeeSearch]);

  // Picking a shift definition prefills its time window — the user can
  // still edit the times afterward, since the definition is only a
  // starting point (denormalized onto the shift, not re-read at save time).
  const applyShiftDefinition = (definitionId: string) => {
    setValue('shiftDefinitionId', definitionId);
    const definition = shiftDefinitions.find((d) => d.id === definitionId);
    if (definition) {
      setValue('startTime', definition.startTime.slice(0, 5));
      setValue('endTime', definition.endTime.slice(0, 5));
      setValue('endsNextDay', definition.isOvernight);
    }
  };

  const onValid = async (values: ShiftFormValues) => {
    setSubmitError(null);
    try {
      const { startsAt, endsAt } = resolveShiftTimestamps(values.date, values.startTime, values.endTime, values.endsNextDay);
      const payload = {
        siteId: values.siteId,
        employeeId: values.employeeId,
        supervisorId: values.supervisorId?.trim() || null,
        shiftDefinitionId: values.shiftDefinitionId?.trim() || null,
        startsAt,
        endsAt,
        notes: values.notes?.trim() || null,
      };
      const saved = shift ? await shiftService.updateShift(shift.id, payload) : await shiftService.createShift(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save the shift.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit shift' : 'Create shift'}
      footer={
        <Button type="submit" form="shift-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="shift-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <div>
          <label htmlFor="shift-site" className="mb-1.5 block text-sm font-medium text-content-primary">
            Site <span className="text-danger-600">*</span>
          </label>
          <select
            id="shift-site"
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
            {...register('siteId')}
          >
            <option value="">Select a site…</option>
            {sites.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
          {errors.siteId && (
            <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
              {errors.siteId.message}
            </p>
          )}
        </div>

        <div>
          <TextField
            label="Employee"
            required
            hint={selectedEmployee ? `Selected: ${selectedEmployee.firstName} ${selectedEmployee.lastName}` : 'Search by name…'}
            placeholder="Search by name…"
            value={employeeSearch}
            onChange={(event) => setEmployeeSearch(event.target.value)}
          />
          <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
            {candidates.map((candidate) => (
              <button
                key={candidate.id}
                type="button"
                onClick={() => {
                  setValue('employeeId', candidate.id, { shouldValidate: true });
                  setSelectedEmployee(candidate);
                }}
                className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                  employeeId === candidate.id
                    ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                    : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
                }`}
              >
                {candidate.firstName} {candidate.lastName}
              </button>
            ))}
          </div>
          {errors.employeeId && (
            <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
              {errors.employeeId.message}
            </p>
          )}
        </div>

        {shiftDefinitions.length > 0 && (
          <div>
            <label htmlFor="shift-definition" className="mb-1.5 block text-sm font-medium text-content-primary">
              Shift definition
            </label>
            <select
              id="shift-definition"
              value={shiftDefinitionId ?? ''}
              onChange={(event) => applyShiftDefinition(event.target.value)}
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
            >
              <option value="">No template (custom times)</option>
              {shiftDefinitions
                .filter((d) => d.status === 'active')
                .map((definition) => (
                  <option key={definition.id} value={definition.id}>
                    {definition.name} ({definition.startTime.slice(0, 5)}–{definition.endTime.slice(0, 5)})
                  </option>
                ))}
            </select>
          </div>
        )}

        <TextField label="Date" type="date" required error={errors.date?.message} {...register('date')} />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Start time" type="time" required error={errors.startTime?.message} {...register('startTime')} />
          <TextField label="End time" type="time" required error={errors.endTime?.message} {...register('endTime')} />
        </div>

        <label className="flex items-center gap-2 text-sm font-medium text-content-primary">
          <input type="checkbox" className="focus-ring h-4 w-4 rounded border-border-strong" {...register('endsNextDay')} />
          Ends next day (overnight shift)
        </label>
        {errors.endsNextDay && (
          <p role="alert" className="-mt-2 text-xs font-medium text-danger-600">
            {errors.endsNextDay.message}
          </p>
        )}

        <TextField label="Notes" placeholder="Optional" error={errors.notes?.message} {...register('notes')} />
      </form>
    </Modal>
  );
}
