import type { ReactNode } from 'react';

export interface PageHeaderProps {
  title: string;
  description?: string;
  /** Pass a fully-wrapped action (its own width/sizing div included) — PageHeader stays unopinionated about button width. */
  action?: ReactNode;
}

/**
 * The title + description + primary-action row every list/overview page
 * already rendered independently. Not used by detail/profile pages, which
 * have their own bespoke identity headers (employee, client, contract).
 */
export function PageHeader({ title, description, action }: PageHeaderProps) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">{title}</h1>
        {description && <p className="mt-1 text-sm text-content-secondary">{description}</p>}
      </div>
      {action}
    </div>
  );
}
