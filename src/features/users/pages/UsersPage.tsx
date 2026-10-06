import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { useAuth } from '@/features/auth/context/authContext';
import { useUsersList } from '@/features/users/hooks/useUsersList';
import { UsersFiltersBar } from '@/features/users/components/UsersFiltersBar';
import { UsersTable } from '@/features/users/components/UsersTable';
import { UsersPagination } from '@/features/users/components/UsersPagination';
import { CreateUserModal } from '@/features/users/components/CreateUserModal';
import { EditUserModal } from '@/features/users/components/EditUserModal';
import { ChangeRoleModal } from '@/features/users/components/ChangeRoleModal';
import { DeactivateUserDialog } from '@/features/users/components/DeactivateUserDialog';
import { canManageUsers } from '@/features/users/utils/userPermissions';
import type { Profile } from '@/types/profile.types';

export function UsersPage() {
  const { user } = useAuth();
  const actorRole = user?.role ?? null;
  const { users, totalCount, page, pageSize, isLoading, error, filters, setFilters, setPage, refetch } =
    useUsersList();

  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<Profile | null>(null);
  const [roleChangeUser, setRoleChangeUser] = useState<Profile | null>(null);
  const [deactivatingUser, setDeactivatingUser] = useState<Profile | null>(null);

  const canManage = canManageUsers(actorRole);

  return (
    <PageContainer>
      <PageHeader
        title="Users"
        description="Manage the user accounts in your organisation."
        action={
          canManage && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)}>
                Add user
              </Button>
            </div>
          )
        }
      />

      <UsersFiltersBar filters={filters} onChange={setFilters} />

      <ErrorAlert message={error} />

      {isLoading ? (
        <LoadingBlock label="Loading users…" />
      ) : (
        <>
          <UsersTable
            users={users}
            actorRole={actorRole}
            onEdit={setEditingUser}
            onChangeRole={setRoleChangeUser}
            onDeactivate={setDeactivatingUser}
          />
          <UsersPagination page={page} pageSize={pageSize} totalCount={totalCount} onPageChange={setPage} />
        </>
      )}

      <CreateUserModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        actorRole={actorRole}
        onCreated={refetch}
      />

      {editingUser && (
        <EditUserModal
          isOpen={Boolean(editingUser)}
          onClose={() => setEditingUser(null)}
          user={editingUser}
          onUpdated={refetch}
        />
      )}
      {roleChangeUser && (
        <ChangeRoleModal
          isOpen={Boolean(roleChangeUser)}
          onClose={() => setRoleChangeUser(null)}
          user={roleChangeUser}
          actorRole={actorRole}
          onRoleChanged={refetch}
        />
      )}
      {deactivatingUser && (
        <DeactivateUserDialog
          isOpen={Boolean(deactivatingUser)}
          onClose={() => setDeactivatingUser(null)}
          user={deactivatingUser}
          onDeactivated={refetch}
        />
      )}
    </PageContainer>
  );
}
