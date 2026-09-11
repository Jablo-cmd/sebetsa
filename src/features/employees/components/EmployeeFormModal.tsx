import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import {
  employeeSchema,
  employeeDefaultValues,
  type EmployeeFormValues,
} from '@/features/employees/schemas/employeeSchema';
import type { Employee, Department, Position } from '@/features/employees/types/employee.types';

export interface EmployeeFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  employee?: Employee | null;
  departments: Department[];
  positions: Position[];
  onSaved: (employee: Employee) => void;
}

export function EmployeeFormModal({ isOpen, onClose, tenantId, employee, departments, positions, onSaved }: EmployeeFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [managerSearch, setManagerSearch] = useState('');
  const [managerCandidates, setManagerCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedManager, setSelectedManager] = useState<EmployeeCandidate | null>(null);
  const isEditing = Boolean(employee);

  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<EmployeeFormValues>({ resolver: zodResolver(employeeSchema), defaultValues: employeeDefaultValues });

  const supervisorId = watch('supervisorId');

  useEffect(() => {
    if (!isOpen) return;
    reset(
      employee
        ? {
            employeeNumber: employee.employeeNumber,
            firstName: employee.firstName,
            lastName: employee.lastName,
            email: employee.email ?? '',
            phone: employee.phone ?? '',
            departmentId: employee.departmentId ?? '',
            positionId: employee.positionId ?? '',
            employmentType: employee.employmentType ?? '',
            employmentStartDate: employee.employmentStartDate,
            supervisorId: employee.supervisorId ?? '',
          }
        : employeeDefaultValues,
    );
    setManagerSearch('');
    setSelectedManager(null);
    setSubmitError(null);
  }, [isOpen, employee, reset]);

  useEffect(() => {
    if (!isOpen || !employee?.supervisorId) return;
    let cancelled = false;
    void employeeService.getEmployee(employee.supervisorId).then((result) => {
      if (!cancelled && result) setSelectedManager({ id: result.id, firstName: result.firstName, lastName: result.lastName });
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, employee?.supervisorId]);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    void employeeService.searchEmployeeCandidates(tenantId, managerSearch, employee?.id).then((results) => {
      if (!cancelled) setManagerCandidates(results);
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, tenantId, managerSearch, employee?.id]);

  const onValid = async (values: EmployeeFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        employeeNumber: values.employeeNumber,
        firstName: values.firstName,
        lastName: values.lastName,
        email: values.email?.trim() || null,
        phone: values.phone?.trim() || null,
        departmentId: values.departmentId?.trim() || null,
        positionId: values.positionId?.trim() || null,
        employmentType: values.employmentType || undefined,
        employmentStartDate: values.employmentStartDate,
        supervisorId: values.supervisorId?.trim() || null,
      };
      const saved = employee
        ? await employeeService.updateEmployee(employee.id, payload)
        : await employeeService.createEmployee(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save employee.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit employee' : 'Add employee'}
      footer={
        <Button type="submit" form="employee-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="employee-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="First name" required error={errors.firstName?.message} {...register('firstName')} />
          <TextField label="Last name" required error={errors.lastName?.message} {...register('lastName')} />
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField
            label="Employee number"
            required
            error={errors.employeeNumber?.message}
            {...register('employeeNumber')}
          />
          <TextField
            label="Start date"
            type="date"
            required
            error={errors.employmentStartDate?.message}
            {...register('employmentStartDate')}
          />
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <TextField label="Email" error={errors.email?.message} {...register('email')} />
          <TextField label="Phone" error={errors.phone?.message} {...register('phone')} />
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="employee-department" className="mb-1.5 block text-sm font-medium text-content-primary">
              Department
            </label>
            <select
              id="employee-department"
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
          <div>
            <label htmlFor="employee-position" className="mb-1.5 block text-sm font-medium text-content-primary">
              Position
            </label>
            <select
              id="employee-position"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('positionId')}
            >
              <option value="">Unassigned</option>
              {positions.map((pos) => (
                <option key={pos.id} value={pos.id}>
                  {pos.title}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="employee-employment-type" className="mb-1.5 block text-sm font-medium text-content-primary">
              Employment type
            </label>
            <select
              id="employee-employment-type"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              {...register('employmentType')}
            >
              <option value="">Not specified</option>
              <option value="full_time">Full time</option>
              <option value="part_time">Part time</option>
              <option value="contract">Contract</option>
              <option value="temporary">Temporary</option>
            </select>
          </div>
        </div>
        <div>
          <TextField
            label="Reports to"
            hint={selectedManager ? `Selected: ${selectedManager.firstName} ${selectedManager.lastName}` : 'Search by name…'}
            placeholder="Search by name…"
            value={managerSearch}
            onChange={(event) => setManagerSearch(event.target.value)}
          />
          <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
            <button
              type="button"
              onClick={() => {
                setValue('supervisorId', '', { shouldValidate: true });
                setSelectedManager(null);
              }}
              className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                !supervisorId
                  ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                  : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
              }`}
            >
              No manager
            </button>
            {managerCandidates.map((candidate) => (
              <button
                key={candidate.id}
                type="button"
                onClick={() => {
                  setValue('supervisorId', candidate.id, { shouldValidate: true });
                  setSelectedManager(candidate);
                }}
                className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                  supervisorId === candidate.id
                    ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                    : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
                }`}
              >
                {candidate.firstName} {candidate.lastName}
              </button>
            ))}
          </div>
          {errors.supervisorId && (
            <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
              {errors.supervisorId.message}
            </p>
          )}
        </div>
      </form>
    </Modal>
  );
}
