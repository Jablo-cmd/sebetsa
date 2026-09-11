import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { siteAssignmentService } from '@/features/siteAssignments/services/siteAssignmentService';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import {
  siteAssignmentSchema,
  siteAssignmentDefaultValues,
  type SiteAssignmentFormValues,
} from '@/features/siteAssignments/schemas/siteAssignmentSchema';
import type { SiteAssignment } from '@/features/siteAssignments/types/siteAssignment.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';

export interface SiteAssignmentFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  assignment?: SiteAssignment | null;
  sites: Site[];
  onSaved: (assignment: SiteAssignment) => void;
}

export function SiteAssignmentFormModal({ isOpen, onClose, tenantId, assignment, sites, onSaved }: SiteAssignmentFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [employeeSearch, setEmployeeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedEmployee, setSelectedEmployee] = useState<EmployeeCandidate | null>(null);
  const isEditing = Boolean(assignment);

  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<SiteAssignmentFormValues>({
    resolver: zodResolver(siteAssignmentSchema),
    defaultValues: siteAssignmentDefaultValues,
  });

  const employeeId = watch('employeeId');

  useEffect(() => {
    if (!isOpen) return;
    reset(
      assignment
        ? {
            siteId: assignment.siteId,
            employeeId: assignment.employeeId,
            roleOnSite: assignment.roleOnSite ?? '',
            startDate: assignment.startDate,
            endDate: assignment.endDate ?? '',
          }
        : siteAssignmentDefaultValues,
    );
    setEmployeeSearch('');
    setSelectedEmployee(null);
    setSubmitError(null);
  }, [isOpen, assignment, reset]);

  useEffect(() => {
    if (!isOpen || !assignment?.employeeId) return;
    let cancelled = false;
    void employeeService.getEmployee(assignment.employeeId).then((result) => {
      if (!cancelled && result) setSelectedEmployee({ id: result.id, firstName: result.firstName, lastName: result.lastName });
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, assignment?.employeeId]);

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

  const onValid = async (values: SiteAssignmentFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        siteId: values.siteId,
        employeeId: values.employeeId,
        roleOnSite: values.roleOnSite?.trim() || null,
        startDate: values.startDate,
        endDate: values.endDate?.trim() || null,
      };
      const saved = assignment
        ? await siteAssignmentService.updateSiteAssignment(assignment.id, payload)
        : await siteAssignmentService.createSiteAssignment(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save site assignment.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit site assignment' : 'Assign employee to site'}
      footer={
        <Button type="submit" form="site-assignment-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="site-assignment-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <div>
          <label htmlFor="assignment-site" className="mb-1.5 block text-sm font-medium text-content-primary">
            Site <span className="text-danger-600">*</span>
          </label>
          <select
            id="assignment-site"
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

        <TextField label="Role on site" placeholder="Cleaner" error={errors.roleOnSite?.message} {...register('roleOnSite')} />

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Start date" type="date" required error={errors.startDate?.message} {...register('startDate')} />
          <TextField label="End date" type="date" error={errors.endDate?.message} {...register('endDate')} />
        </div>
      </form>
    </Modal>
  );
}
