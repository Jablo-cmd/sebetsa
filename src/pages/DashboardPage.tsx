import { useAuth } from '@/features/auth/context/authContext';
import { useProfile } from '@/features/profile/context/profileContext';
import { useTenant } from '@/features/tenant/context/tenantContext';
import { rbacService } from '@/features/rbac/services/rbacService';
import {
  DashboardScreen,
  DashboardHeading,
  NoOrganizationSelectedState,
} from '@/features/dashboard/components/DashboardPrimitives';
import { WorkspaceDashboard } from '@/features/dashboard/personas/WorkspaceDashboard';

/**
 * `/dashboard` is composed entirely from the signed-in role's own resolved
 * navigation (see WorkspaceDashboard) — no bespoke per-role dashboard with
 * hand-picked KPIs yet. Real, role-scoped widgets (staffing gaps, incidents,
 * SLA status) are a Phase 2 addition once those domains have data to show.
 */
export function DashboardPage() {
  const { user } = useAuth();
  const { profile } = useProfile();
  const { tenant } = useTenant();
  const isPlatformLevel = rbacService.can(user?.role ?? null, 'tenant.switch');

  if (isPlatformLevel && !tenant?.organization) {
    return (
      <DashboardScreen>
        <DashboardHeading
          title={`Welcome back${profile?.firstName ? `, ${profile.firstName}` : ''}`}
          subtitle={profile?.role ? profile.role.replace(/_/g, ' ') : 'No role assigned'}
        />
        <NoOrganizationSelectedState />
      </DashboardScreen>
    );
  }

  return <WorkspaceDashboard />;
}
