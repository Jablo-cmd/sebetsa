import { Link } from 'react-router-dom';
import { usePermissions } from '@/hooks/usePermissions';

export interface NoActiveOrganizationNoticeProps {
  /** Lower-case plural noun for the thing being managed, e.g. "employees", "sites". */
  resource: string;
}

/**
 * Shown in place of a create/manage workflow when there's no active
 * organization — this only happens for platform-level roles (tenant_id is
 * NULL by design; see is_platform_admin()), since every tenant-scoped role
 * always has one.
 */
export function NoActiveOrganizationNotice({ resource }: NoActiveOrganizationNoticeProps) {
  const { can } = usePermissions();
  const canSwitchTenant = can('tenant.switch');

  return (
    <div className="rounded-card border border-dashed border-border-strong bg-surface-raised px-4 py-10 text-center">
      <p className="text-sm font-medium text-content-primary">No organization selected</p>
      <p className="mx-auto mt-1 max-w-sm text-sm text-content-secondary">
        {canSwitchTenant
          ? `Select or create an organization before managing ${resource}.`
          : "Your account isn't linked to an organization yet. Please contact your administrator."}
      </p>
      {canSwitchTenant && (
        <Link
          to="/organizations"
          className="focus-ring mt-4 inline-flex h-10 items-center justify-center rounded-md bg-brand-600 px-4 text-sm font-semibold text-white transition-colors duration-150 hover:bg-brand-500"
        >
          Go to Organizations
        </Link>
      )}
    </div>
  );
}
