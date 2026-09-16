import { useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { AlertTriangleIcon } from '@/components/ui/icons';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { emergencyService } from '@/features/emergency/services/emergencyService';
import { useDeviceLocation } from '@/lib/useDeviceLocation';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { EmergencyType } from '@/features/emergency/types/emergency.types';

const TYPE_OPTIONS: { value: EmergencyType; label: string }[] = [
  { value: 'panic', label: 'Panic / duress' },
  { value: 'medical', label: 'Medical emergency' },
  { value: 'security_threat', label: 'Security threat' },
  { value: 'other', label: 'Other emergency' },
];

/**
 * Omnipresent, ungated by permission — every authenticated, tenant-gated
 * employee can trigger an emergency (same "no guard needed" posture as
 * /dashboard/notifications). Rendered once in DashboardLayout; renders
 * nothing for a signed-in user with no linked employee record (client_user,
 * a platform admin with no operational identity) since trigger_emergency()
 * requires one server-side anyway.
 */
export function PanicButton() {
  const { data: employee } = useMyEmployee();
  const { read: readLocation } = useDeviceLocation();
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [selectedType, setSelectedType] = useState<EmergencyType>('panic');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [triggeredAt, setTriggeredAt] = useState<string | null>(null);

  if (!employee) return null;

  const handleClose = () => {
    setIsModalOpen(false);
    setError(null);
    setTriggeredAt(null);
    setSelectedType('panic');
  };

  const handleTrigger = async () => {
    setIsSubmitting(true);
    setError(null);
    try {
      const location = await readLocation();
      const event = await emergencyService.triggerEmergency(location, selectedType);
      setTriggeredAt(event.triggeredAt);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to trigger the emergency alert. If you are in immediate danger, call local emergency services.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <>
      <button
        type="button"
        onClick={() => setIsModalOpen(true)}
        aria-label="Trigger emergency alert"
        className="focus-ring fixed bottom-6 right-6 z-20 flex h-14 w-14 items-center justify-center rounded-full bg-danger-600 text-white shadow-card transition-colors hover:bg-danger-500 dark:shadow-card-dark"
      >
        <AlertTriangleIcon className="h-6 w-6" />
      </button>

      <Modal isOpen={isModalOpen} onClose={handleClose} title="Trigger an emergency alert">
        {triggeredAt ? (
          <div className="text-center">
            <p className="text-sm font-medium text-content-primary">Your emergency alert has been sent.</p>
            <p className="mt-1 text-xs text-content-tertiary">Triggered at {new Date(triggeredAt).toLocaleTimeString()}. Your supervisor and operations team have been notified.</p>
            <Button className="mt-4" onClick={handleClose}>
              Close
            </Button>
          </div>
        ) : (
          <div className="flex flex-col gap-4">
            <ErrorAlert message={error} />
            <p className="text-sm text-content-secondary">
              This immediately alerts your supervisor and operations team with your current location. Only use this for a real emergency.
            </p>
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-1 text-sm font-medium text-content-primary">Type of emergency</legend>
              {TYPE_OPTIONS.map((option) => (
                <label key={option.value} className="flex items-center gap-2 text-sm text-content-primary">
                  <input
                    type="radio"
                    name="emergency-type"
                    value={option.value}
                    checked={selectedType === option.value}
                    onChange={() => setSelectedType(option.value)}
                    className="h-4 w-4"
                  />
                  {option.label}
                </label>
              ))}
            </fieldset>
            <Button
              className="bg-danger-600 hover:bg-danger-500 active:bg-danger-800"
              onClick={() => void handleTrigger()}
              isLoading={isSubmitting}
            >
              Confirm — send emergency alert now
            </Button>
          </div>
        )}
      </Modal>
    </>
  );
}
