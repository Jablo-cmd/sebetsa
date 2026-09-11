import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { userService } from '@/features/users/services/userService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { canAssignRole } from '@/features/users/utils/userPermissions';
import { ASSIGNABLE_ROLES, ASSIGNABLE_ROLE_LABELS } from '@/features/users/types/user.types';
import type { AssignableRole } from '@/features/users/types/user.types';
import type { UserRole } from '@/features/auth/types/auth.types';
import type { Profile } from '@/types/profile.types';

export interface ChangeRoleModalProps {
  isOpen: boolean;
  onClose: () => void;
  user: Profile;
  actorRole: UserRole | null;
  onRoleChanged: () => void;
}

export function ChangeRoleModal({ isOpen, onClose, user, actorRole, onRoleChanged }: ChangeRoleModalProps) {
  const [selectedRole, setSelectedRole] = useState<AssignableRole>(
    (ASSIGNABLE_ROLES as readonly string[]).includes(user.role ?? '') ? (user.role as AssignableRole) : 'employee',
  );
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  useEffect(() => {
    if (isOpen) {
      setSelectedRole(
        (ASSIGNABLE_ROLES as readonly string[]).includes(user.role ?? '') ? (user.role as AssignableRole) : 'employee',
      );
      setSubmitError(null);
    }
  }, [isOpen, user.role]);

  const assignableRoles = ASSIGNABLE_ROLES.filter((role) => canAssignRole(actorRole, role, user.role));

  const handleConfirm = async () => {
    setSubmitError(null);
    setIsSubmitting(true);
    try {
      await userService.updateUserRole(user.id, selectedRole);
      onRoleChanged();
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to update role.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Change role"
      footer={
        <Button type="button" onClick={() => void handleConfirm()} isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Confirm change'}
        </Button>
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
          Choose a new role for{' '}
          <span className="font-medium text-content-primary">
            {user.firstName} {user.lastName}
          </span>
          .
        </p>

        <div>
          <label htmlFor="change-role-select" className="mb-1.5 block text-sm font-medium text-content-primary">
            Role
          </label>
          <select
            id="change-role-select"
            value={selectedRole}
            onChange={(event) => setSelectedRole(event.target.value as AssignableRole)}
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
          >
            {assignableRoles.map((role) => (
              <option key={role} value={role}>
                {ASSIGNABLE_ROLE_LABELS[role]}
              </option>
            ))}
          </select>
          {assignableRoles.length === 0 && (
            <p className="mt-1.5 text-xs text-content-tertiary">
              You don&apos;t have permission to assign a different role to this user.
            </p>
          )}
        </div>
      </div>
    </Modal>
  );
}