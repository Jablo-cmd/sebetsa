import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { useAuth } from '@/features/auth/context/authContext';
import { useNotifications } from '@/features/notifications/hooks/useNotifications';
import type { Notification } from '@/features/notifications/types/notification.types';

function formatDateTime(value: string): string {
  return new Date(value).toLocaleString('en-ZA', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function NotificationsPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { notifications, unreadCount, isLoading, error, markRead, markAllRead } = useNotifications(user?.id);

  const handleOpen = async (notification: Notification) => {
    if (!notification.isRead) {
      // A failed update stays visible (ErrorAlert) instead of silently
      // navigating away from the problem.
      const ok = await markRead(notification.id);
      if (!ok) return;
    }
    if (notification.linkPath) {
      navigate(notification.linkPath);
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Notifications"
        description="Updates addressed to you."
        action={
          unreadCount > 0 && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" variant="secondary" onClick={() => void markAllRead()}>
                Mark all as read
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={error} />

      {isLoading ? (
        <LoadingBlock label="Loading notifications…" />
      ) : notifications.length === 0 ? (
        <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
          Nothing here yet.
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {notifications.map((notification) => (
            <li key={notification.id}>
              <button
                type="button"
                onClick={() => void handleOpen(notification)}
                className={`focus-ring flex w-full flex-col gap-1 rounded-card border px-4 py-3.5 text-left transition-colors ${
                  notification.isRead
                    ? 'border-border bg-surface-raised'
                    : 'border-brand-500/40 bg-brand-50 dark:bg-brand-500/10'
                }`}
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="font-medium text-content-primary">{notification.title}</span>
                  {!notification.isRead && (
                    <span aria-hidden="true" className="h-2 w-2 shrink-0 rounded-full bg-brand-600" />
                  )}
                </div>
                <p className="text-sm text-content-secondary">{notification.body}</p>
                <span className="text-xs text-content-tertiary">{formatDateTime(notification.createdAt)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </PageContainer>
  );
}
