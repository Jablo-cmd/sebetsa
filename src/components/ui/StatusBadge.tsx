export type StatusTone = 'neutral' | 'info' | 'success' | 'warning' | 'danger';

const TONE_CLASSES: Record<StatusTone, string> = {
  neutral: 'bg-surface-sunken text-content-secondary',
  info: 'bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-200',
  success: 'bg-success-500/10 text-success-500',
  warning: 'bg-warning-50 text-warning-600 dark:bg-warning-500/15 dark:text-warning-500',
  danger: 'bg-danger-50 text-danger-600 dark:bg-danger-500/15 dark:text-danger-500',
};

export interface StatusBadgeProps {
  label: string;
  tone: StatusTone;
}

/**
 * The single status-pill treatment for every lifecycle status across
 * Sebetsa (incidents, procurement, assets, compliance, contracts, tasks,
 * training…) — replaces the same `inline-flex items-center rounded-full
 * px-2.5 py-1 text-xs font-medium` markup that had been copy-pasted with a
 * bespoke color map into each feature page independently. Callers supply
 * only a label and a semantic tone; the five tones map to the same
 * success/warning/danger/info/neutral vocabulary used everywhere else in
 * the design system, never an arbitrary color choice per page.
 */
export function StatusBadge({ label, tone }: StatusBadgeProps) {
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium capitalize ${TONE_CLASSES[tone]}`}>
      {label}
    </span>
  );
}
