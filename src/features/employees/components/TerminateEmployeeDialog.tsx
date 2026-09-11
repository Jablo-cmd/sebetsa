import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { employeeService } from '@/features/employees/services/employeeService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { Employee } from '@/features/employees/types/employee.types';

export interface TerminateEmployeeDialogProps {
  isOpen: boolean;
  onClose: () => void;
  employee: Employee;
  onTerminated: (employee: Employee) => void;
}

const today = () => new Date().toISOString().slice(0, 10);

export function TerminateEmployeeDialog({ isOpen, onClose, employee, onTerminated }: TerminateEmployeeDialogProps) {
  const [terminationDate, setTerminationDate] = useState(today);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  const handleConfirm = async () => {
    setSubmitError(null);
    setIsSubmitting(true);
    try {
      const updated = await employeeService.terminate(employee.id, terminationDate);
      onTerminated(updated);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to terminate employee.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Terminate employee"
      footer={
        <div className="flex justify-end gap-3">
          <div className="w-28">
            <Button type="button" variant="secondary" onClick={onClose}>
              Cancel
            </Button>
          </div>
          <div className="w-40">
            <Button type="button" onClick={() => void handleConfirm()} isLoading={isSubmitting}>
              {isSubmitting ? 'Terminating…' : 'Terminate'}
            </Button>
          </div>
        </div>
      }
    >
      <div className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}
        <p className="text-sm text-content-secondary">
          <span className="font-medium text-content-primary">
            {employee.firstName} {employee.lastName}
          </span>{' '}
          will be marked terminated. If they have a linked login, it will also be deactivated. This does not delete
          their employee record.
        </p>
        <TextField
          label="Termination date"
          type="date"
          required
          min={employee.employmentStartDate}
          value={terminationDate}
          onChange={(event) => setTerminationDate(event.target.value)}
        />
      </div>
    </Modal>
  );
}
