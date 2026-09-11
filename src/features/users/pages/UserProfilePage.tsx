import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { useAuth } from '@/features/auth/context/authContext';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useUserProfile } from '@/features/users/hooks/useUserProfile';
import { EditUserModal } from '@/features/users/components/EditUserModal';
import { ChangeRoleModal } from '@/features/users/components/ChangeRoleModal';
import { DeactivateUserDialog } from '@/features/users/components/DeactivateUserDialog';
import { canManageUser } from '@/features/users/utils/userPermissions';

export function UserProfilePage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user: actor } = useAuth();
  const actorRole = actor?.role ?? null;
  const currentOrganization = useCurrentOrganization();
  const { user, isLoading, error, refetch } = useUserProfile(id);

  const [isEditOpen, setIsEditOpen] = useState(false);
  const [isRoleOpen, setIsRoleOpen] = useState(false);
  const [isDeactivateOpen, setIsDeactivateOpen] = useState(false);

  if (isLoading) {
    return <FullScreenSpinner label="Loading user…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!user) {
    return (
      <FullScreenNotice
        title="User not found"
        message="This user doesn't exist, or you don't have access to view them."
        action={
          <Link to="/users" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Users
          </Link>
        }
      />
    );
  }

  const canManage = canManageUser(actorRole, user.role);

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/users')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Users
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex items-center gap-4">
          <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-brand-600 text-lg font-semibold text-white">
            {user.firstName[0]}
            {user.lastName[0]}
          </span>
          <div>
            <h1 className="text-xl font-bold text-content-primary">
              {user.firstName} {user.lastName}
            </h1>
            <p className="text-sm text-content-secondary">{user.email}</p>
          </div>
        </div>

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Role</dt>
            <dd className="mt-1 text-sm font-medium capitalize text-content-primary">
              {user.role ? user.role.replace(/_/g, ' ') : 'No role assigned'}
            </dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Status</dt>
            <dd className="mt-1 text-sm font-medium capitalize text-content-primary">{user.status}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Phone</dt>
            <dd className="mt-1 text-sm text-content-primary">{user.phone ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">
              School association
            </dt>
            <dd className="mt-1 text-sm text-content-primary">
              {user.tenantId ? (currentOrganization?.name ?? 'Your organization') : 'No organization assigned (platform-level account)'}
            </dd>
          </div>
        </dl>

        {canManage && (
          <div className="mt-6 flex flex-wrap gap-3 border-t border-border pt-5">
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" onClick={() => setIsEditOpen(true)}>
                Edit profile
              </Button>
            </div>
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" onClick={() => setIsRoleOpen(true)}>
                Change role
              </Button>
            </div>
            {user.status === 'active' && (
              <div className="w-full sm:w-auto sm:min-w-[8rem]">
                <Button type="button" variant="secondary" onClick={() => setIsDeactivateOpen(true)}>
                  Deactivate
                </Button>
              </div>
            )}
          </div>
        )}
      </div>

      <EditUserModal isOpen={isEditOpen} onClose={() => setIsEditOpen(false)} user={user} onUpdated={refetch} />
      <ChangeRoleModal
        isOpen={isRoleOpen}
        onClose={() => setIsRoleOpen(false)}
        user={user}
        actorRole={actorRole}
        onRoleChanged={refetch}
      />
      <DeactivateUserDialog
        isOpen={isDeactivateOpen}
        onClose={() => setIsDeactivateOpen(false)}
        user={user}
        onDeactivated={refetch}
      />
    </div>
  );
}
