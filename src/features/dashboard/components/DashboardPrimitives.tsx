import type { ComponentType, ReactNode, SVGProps } from 'react';
import { Link } from 'react-router-dom';
import { BuildingIcon } from '@/components/ui/icons';

interface StatPanelProps {
  label: string;
  value: ReactNode;
  caption: string;
  to: string;
  isLoading?: boolean;
}

export function StatPanel({ label, value, caption, to, isLoading }: StatPanelProps) {
  return (
    <Link
      to={to}
      className="focus-ring flex flex-col gap-1.5 rounded-card border border-border bg-surface-raised px-4 py-3.5 transition-colors hover:border-brand-400 dark:hover:border-brand-500"
    >
      <span className="text-[11px] font-semibold uppercase tracking-wider text-content-tertiary">{label}</span>
      {isLoading ? (
        <span className="block h-7 w-20 animate-pulse rounded bg-surface-sunken" aria-hidden="true" />
      ) : (
        <span className="font-mono text-2xl font-semibold leading-none text-content-primary">{value}</span>
      )}
      <span className="text-xs text-content-tertiary">{caption}</span>
    </Link>
  );
}

export function InfoPanel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="rounded-card border border-border bg-surface-raised p-4">
      <h2 className="mb-3 text-xs font-semibold uppercase tracking-wider text-content-tertiary">{title}</h2>
      {children}
    </section>
  );
}

export function EmptyPanelMessage({ message }: { message: string }) {
  return (
    <p className="flex h-full min-h-[5.5rem] items-center justify-center text-center text-xs text-content-tertiary">
      {message}
    </p>
  );
}

export interface QuickAction {
  label: string;
  description?: string;
  to: string;
  icon: ComponentType<SVGProps<SVGSVGElement>>;
}

export function QuickActionsPanel({ actions }: { actions: QuickAction[] }) {
  if (actions.length === 0) return null;
  return (
    <InfoPanel title="Quick Actions">
      <div className="flex flex-col divide-y divide-border">
        {actions.map(({ label, description, to, icon: Icon }) => (
          <Link
            key={label}
            to={to}
            className="focus-ring flex items-center gap-3 py-2.5 transition-colors first:pt-0 last:pb-0 hover:text-brand-600 dark:hover:text-brand-300"
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
              <Icon className="h-4 w-4" />
            </span>
            <span className="min-w-0">
              <span className="block text-sm font-medium text-content-primary">{label}</span>
              {description && (
                <span className="block truncate text-xs text-content-tertiary">{description}</span>
              )}
            </span>
          </Link>
        ))}
      </div>
    </InfoPanel>
  );
}

export function DashboardHeading({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div>
      <h1 className="text-xl font-semibold text-content-primary">{title}</h1>
      {subtitle && <p className="mt-0.5 text-sm text-content-secondary">{subtitle}</p>}
    </div>
  );
}

export function DashboardScreen({ children }: { children: ReactNode }) {
  return <div className="flex flex-col gap-5 px-4 py-6 sm:px-6">{children}</div>;
}

/**
 * Shown to a platform-level admin who hasn't selected an organization yet —
 * every tenant-scoped widget would otherwise be a wall of misleading zeros.
 */
export function NoOrganizationSelectedState() {
  return (
    <div className="flex flex-col items-center gap-4 rounded-card border border-dashed border-border-strong bg-surface-raised px-6 py-14 text-center">
      <span className="flex h-12 w-12 items-center justify-center rounded-full bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
        <BuildingIcon className="h-6 w-6" />
      </span>
      <div>
        <p className="text-base font-semibold text-content-primary">No organization selected</p>
        <p className="mx-auto mt-1 max-w-md text-sm text-content-secondary">
          As a platform administrator you operate across every organization. Create the first one, or switch into an
          existing one, to manage its records.
        </p>
      </div>
      <Link
        to="/organizations"
        className="focus-ring inline-flex h-11 items-center justify-center rounded-md bg-brand-600 px-5 text-sm font-semibold text-white transition-colors duration-150 hover:bg-brand-500"
      >
        Go to Organizations
      </Link>
    </div>
  );
}
