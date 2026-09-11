import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { useTenant } from '@/features/tenant/context/tenantContext';
import { OrganizationsTable } from '@/features/tenant/components/OrganizationsTable';
import { CreateOrganizationModal } from '@/features/tenant/components/CreateOrganizationModal';
import { getDbErrorMessage } from '@/lib/dbErrors';
import type { Organization } from '@/types/organization.types';

/**
 * The platform-admin onboarding + tenant-switching hub. Reachable only by
 * roles with the `tenant.switch` permission (see RequirePermission on the
 * /organizations route) — tenant-scoped roles already belong to a single
 * organization and never need this page.
 */
export function OrganizationsPage() {
  const navigate = useNavigate();
  const { tenant, availableOrganizations, availableOrganizationsLoading, switchTenant } = useTenant();

  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [switchingId, setSwitchingId] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const handleSwitch = async (organization: Organization) => {
    setActionError(null);
    setSwitchingId(organization.id);
    try {
      await switchTenant(organization.id);
      navigate('/dashboard');
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to switch organization.'));
    } finally {
      setSwitchingId(null);
    }
  };

  const handleCreated = () => {
    navigate('/dashboard');
  };

  return (
    <PageContainer>
      <PageHeader
        title="Organizations"
        description="Onboard a new organization, or switch which one you're currently managing."
        action={
          <Button type="button" onClick={() => setIsCreateOpen(true)}>
            Create organization
          </Button>
        }
      />

      <ErrorAlert message={actionError} />

      {availableOrganizationsLoading ? (
        <LoadingBlock label="Loading organizations…" />
      ) : (
        <OrganizationsTable
          organizations={availableOrganizations}
          activeOrganizationId={tenant?.id ?? null}
          onSwitch={(organization) => void handleSwitch(organization)}
          switchingId={switchingId}
        />
      )}

      <CreateOrganizationModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        onCreated={handleCreated}
      />
    </PageContainer>
  );
}
