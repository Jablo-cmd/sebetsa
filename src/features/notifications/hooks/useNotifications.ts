import { useCallback, useEffect, useMemo, useState } from 'react';
import { notificationService } from '@/features/notifications/services/notificationService';
import type { Notification } from '@/features/notifications/types/notification.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseNotificationsResult {
  notifications: Notification[];
  unreadCount: number;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  /** Resolves true when the notification was marked read; false (with `error` set) when it failed. */
  markRead: (id: string) => Promise<boolean>;
  markAllRead: () => Promise<boolean>;
}

export function useNotifications(recipientProfileId: string | undefined): UseNotificationsResult {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!recipientProfileId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setNotifications(await notificationService.getMyNotifications(recipientProfileId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load notifications.'));
    } finally {
      setIsLoading(false);
    }
  }, [recipientProfileId]);

  useEffect(() => {
    void load();
  }, [load]);

  const markRead = useCallback(
    async (id: string) => {
      try {
        await notificationService.markRead(id);
      } catch (err) {
        setError(getDbErrorMessage(err, 'Failed to update the notification.'));
        return false;
      }
      await load();
      return true;
    },
    [load],
  );

  const markAllRead = useCallback(async () => {
    if (!recipientProfileId) return false;
    try {
      await notificationService.markAllRead(recipientProfileId);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to update your notifications.'));
      return false;
    }
    await load();
    return true;
  }, [recipientProfileId, load]);

  const unreadCount = useMemo(() => notifications.filter((n) => !n.isRead).length, [notifications]);

  return { notifications, unreadCount, isLoading, error, refetch: load, markRead, markAllRead };
}
