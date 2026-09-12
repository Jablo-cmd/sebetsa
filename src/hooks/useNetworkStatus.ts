import { useEffect, useState } from 'react';

/** Real browser online/offline state (navigator.onLine + the events it
 * fires) — not a simulation. Used to warn field workers before they act,
 * not to queue/replay actions: Sebetsa does not claim offline support (see
 * docs on Phase L's deferred offline-sync scope). */
export function useNetworkStatus(): boolean {
  const [isOnline, setIsOnline] = useState(() => (typeof navigator === 'undefined' ? true : navigator.onLine));

  useEffect(() => {
    const goOnline = () => setIsOnline(true);
    const goOffline = () => setIsOnline(false);
    window.addEventListener('online', goOnline);
    window.addEventListener('offline', goOffline);
    return () => {
      window.removeEventListener('online', goOnline);
      window.removeEventListener('offline', goOffline);
    };
  }, []);

  return isOnline;
}
