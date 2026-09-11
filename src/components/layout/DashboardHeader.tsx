import { Link, useLocation } from 'react-router-dom';
import { Logo } from '@/components/ui/Logo';
import { ThemeToggle } from '@/components/ui/ThemeToggle';
import { MenuIcon } from '@/components/ui/icons';
import { UserMenu } from '@/components/layout/UserMenu';
import { NotificationBell } from '@/features/notifications/components/NotificationBell';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { usePermissions } from '@/hooks/usePermissions';
import { getPageTitle } from '@/lib/pageTitles';

export interface DashboardHeaderProps {
  onMenuClick: () => void;
}

/**
 * The title/section text below is a breadcrumb-style label, not a heading —
 * every page already renders its own canonical <h1>, and a second <h1> here
 * would both break single-H1-per-page accessibility and make every
 * `getByRole('heading', ...)` query in the app ambiguous.
 */
export function DashboardHeader({ onMenuClick }: DashboardHeaderProps) {
  const organization = useCurrentOrganization();
  const { can } = usePermissions();
  const { pathname } = useLocation();
  const { title, section } = getPageTitle(pathname);
  const canSwitchTenant = can('tenant.switch');

  return (
    <header className="flex h-[4.5rem] shrink-0 items-center justify-between gap-4 border-b border-border bg-surface-raised px-4 sm:px-6">
      <div className="flex min-w-0 items-center gap-3">
        <button
          type="button"
          onClick={onMenuClick}
          aria-label="Open menu"
          className="focus-ring -ml-1 shrink-0 rounded-md p-1.5 text-content-secondary hover:text-content-primary md:hidden"
        >
          <MenuIcon className="h-5 w-5" />
        </button>

        <div className="hidden md:block">
          <Logo />
        </div>

        <div className="hidden h-9 w-px bg-border md:block" />

        <div className="min-w-0">
          <p className="truncate text-lg font-semibold leading-tight text-content-primary">
            {title}
          </p>
          <p className="truncate font-mono text-xs uppercase tracking-wide text-content-tertiary">
            {section}
          </p>
        </div>
      </div>

      <div className="flex shrink-0 items-center gap-3">
        <span className="hidden max-w-[16rem] truncate text-right sm:block">
          <span className="block text-sm font-medium text-content-secondary">
            {organization?.name ?? 'No organization selected'}
          </span>
        </span>
        {canSwitchTenant && (
          <Link
            to="/organizations"
            className="focus-ring hidden h-9 shrink-0 items-center rounded-md border border-border-strong px-3 text-xs font-medium text-content-secondary transition-colors hover:bg-surface-sunken hover:text-content-primary sm:flex"
          >
            Switch organization
          </Link>
        )}
        <div className="hidden h-9 w-px bg-border sm:block" />
        <NotificationBell to="/notifications" />
        <ThemeToggle />
        <UserMenu />
      </div>
    </header>
  );
}
