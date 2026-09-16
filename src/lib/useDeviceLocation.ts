import { useCallback, useState } from 'react';
import type { DeviceLocation } from '@/features/attendance/types/attendance.types';

export interface UseDeviceLocationResult {
  isReading: boolean;
  /** true once a read has been attempted and the device denied/failed to produce a location — distinct from never having tried. */
  wasDenied: boolean;
  /**
   * Reads the device's current position once. Never throws — a failure
   * (denied permission, unsupported browser, timeout) resolves to `null`
   * so callers can still submit the action with `p_gps_denied: true` rather
   * than being blocked outright; the server records the failure as
   * evidence (`location_unavailable`) instead of silently dropping it.
   */
  read: () => Promise<DeviceLocation | null>;
}

/**
 * Thin wrapper over `navigator.geolocation` — the raw coordinates/accuracy
 * this returns are passed straight to a server RPC (clock_in/clock_out/
 * scan_checkpoint/trigger_emergency); this hook never computes or claims a
 * verification decision itself. Matches the codebase's established "honest
 * capability" posture (see src/hooks/useNetworkStatus.ts) — an unsupported
 * or denied read is reported as such, never silently treated as success.
 */
export function useDeviceLocation(): UseDeviceLocationResult {
  const [isReading, setIsReading] = useState(false);
  const [wasDenied, setWasDenied] = useState(false);

  const read = useCallback((): Promise<DeviceLocation | null> => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      setWasDenied(true);
      return Promise.resolve(null);
    }

    setIsReading(true);
    setWasDenied(false);

    return new Promise((resolve) => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          setIsReading(false);
          resolve({
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracyMeters: position.coords.accuracy ?? null,
            capturedAt: new Date(position.timestamp).toISOString(),
          });
        },
        () => {
          setIsReading(false);
          setWasDenied(true);
          resolve(null);
        },
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
      );
    });
  }, []);

  return { isReading, wasDenied, read };
}
