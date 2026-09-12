import type { ReactNode } from 'react';

export interface CardProps {
  title: string;
  /** Rendered top-right of the header, e.g. a status pill or a "View all" link. */
  action?: ReactNode;
  children: ReactNode;
}

/**
 * The section/summary card wrapper shared across Sebetsa's detail and
 * dashboard pages — rounded-card border bg-surface-raised p-4 with an
 * uppercase label heading, extracted once instead of repeated markup.
 */
export function Card({ title, action, children }: CardProps) {
  return (
    <section className="flex flex-col gap-3 rounded-card border border-border bg-surface-raised p-4">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-xs font-semibold uppercase tracking-wider text-content-tertiary">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}
