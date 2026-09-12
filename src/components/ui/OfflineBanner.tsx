import { useNetworkStatus } from '@/hooks/useNetworkStatus';

/**
 * Shown on field-critical pages (clock in/out, task completion, leave
 * submission) so a worker knows *before* tapping a button that it will
 * fail, rather than discovering it via a confusing error afterward.
 * Deliberately not an offline queue — Sebetsa does not claim offline
 * support; this is honest status, not simulated capability.
 */
export function OfflineBanner() {
  const isOnline = useNetworkStatus();
  if (isOnline) return null;

  return (
    <div role="status" className="rounded-lg border border-warning-500/30 bg-warning-50 px-3.5 py-2.5 text-sm font-medium text-warning-700 dark:bg-warning-500/15 dark:text-warning-200">
      You're offline. Actions here need a connection and won't be saved until you're back online.
    </div>
  );
}
