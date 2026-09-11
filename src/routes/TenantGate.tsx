import { Outlet } from 'react-router-dom';
import { useProfile } from '@/features/profile/context/profileContext';
import { useTenant } from '@/features/tenant/context/tenantContext';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';

/**
 * Sits inside ProtectedRoute: an authenticated, verified user might still
 * have no profile row, no tenant assignment, or belong to a suspended
 * organization. Each of those gets its own graceful message instead of a blank
 * or broken page.
 */
export function TenantGate() {
  const { status: profileStatus, profile, error: profileError } = useProfile();
  const { status: tenantStatus, tenant, error: tenantError } = useTenant();

  if (profileStatus === 'idle' || profileStatus === 'loading') {
    return <FullScreenSpinner label="Loading your profile…" />;
  }

  if (profileStatus === 'missing') {
    return (
      <FullScreenNotice
        title="Profile not found"
        message="We couldn't find a profile for your account. Please contact your organization administrator."
      />
    );
  }

  if (profileStatus === 'error') {
    return (
      <FullScreenNotice
        title="Something went wrong"
        message={profileError ?? 'Failed to load your profile.'}
      />
    );
  }

  if (profile && profile.status !== 'active') {
    return (
      <FullScreenNotice
        title="Account deactivated"
        message="Your account has been deactivated. Please contact your organization administrator."
      />
    );
  }

  if (tenantStatus === 'idle' || tenantStatus === 'loading') {
    return <FullScreenSpinner label="Loading your organization…" />;
  }

  if (tenantStatus === 'missing') {
    return (
      <FullScreenNotice
        title="No organization assigned"
        message="Your account isn't linked to an organization yet. Please contact your administrator."
      />
    );
  }

  if (tenantStatus === 'inactive') {
    return (
      <FullScreenNotice
        title="Organization inactive"
        message={`${tenant?.organization.name ?? 'This organization'}'s account is currently inactive. Please contact your administrator.`}
      />
    );
  }

  if (tenantStatus === 'error') {
    return (
      <FullScreenNotice
        title="Something went wrong"
        message={tenantError ?? 'Failed to load your organization.'}
      />
    );
  }

  return <Outlet />;
}
