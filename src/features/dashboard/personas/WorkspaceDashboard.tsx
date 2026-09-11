import { useProfile } from '@/features/profile/context/profileContext';
import { useTenant } from '@/features/tenant/context/tenantContext';
import { useAuth } from '@/features/auth/context/authContext';
import { resolveNavForRole } from '@/features/rbac/constants/navigation';
import {
  DashboardHeading,
  DashboardScreen,
  InfoPanel,
  QuickActionsPanel,
  type QuickAction,
} from '@/features/dashboard/components/DashboardPrimitives';

/**
 * Built entirely from the role's own resolved navigation — so it can only
 * ever surface functions the role genuinely has (e.g. an employee gets
 * Scheduling + Attendance + Tasks; a site_manager additionally gets
 * Workforce). No placeholders, no advertising of anything unbuilt.
 */
export function WorkspaceDashboard() {
  const { user } = useAuth();
  const { profile } = useProfile();
  const { tenant } = useTenant();

  const nav = resolveNavForRole(user?.role ?? null);
  const items = nav.flatMap((g) => g.items);
  const workspaceItems = items.filter((i) => i.path !== '/dashboard' && i.path !== '/my-profile');
  const substantiveItems = workspaceItems.filter(
    (i) => !['/messages', '/announcements', '/notifications/settings'].includes(i.path),
  );

  const quickActions: QuickAction[] = workspaceItems
    .slice(0, 6)
    .map((i) => ({ label: i.label, description: '', to: i.path, icon: i.icon }));

  return (
    <DashboardScreen>
      <DashboardHeading
        title={`Welcome${profile?.firstName ? `, ${profile.firstName}` : ''}`}
        subtitle={`${profile?.role ? profile.role.replace(/_/g, ' ') : 'Team member'}${
          tenant?.organization.name ? ` at ${tenant.organization.name}` : ''
        }`}
      />

      <InfoPanel title="Your Workspace">
        <p className="text-sm text-content-secondary">
          {substantiveItems.length > 0
            ? `Your workspace covers ${substantiveItems.map((i) => i.label).join(', ')}, plus messages and announcements.`
            : 'Your workspace currently covers messages, announcements and your profile.'}
        </p>
      </InfoPanel>

      <QuickActionsPanel actions={quickActions} />
    </DashboardScreen>
  );
}
