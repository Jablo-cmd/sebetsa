import { Link } from 'react-router-dom';
import { useAuth } from '@/features/auth/context/authContext';
import { useNotifications } from '@/features/notifications/hooks/useNotifications';
import { BellIcon } from '@/components/ui/icons';

export interface NotificationBellProps {
  /** Route of the notifications list the bell links to. */
  to: string;
}

/**
 * Links through to a notifications page rather than a popover — simpler,
 * keyboard/screen-reader-friendly by default (a real page, not a
 * roving-focus widget), and easier to test end-to-end. The unread badge is
 * the only thing rendered inline in the header.
 */
export function NotificationBell({ to }: NotificationBellProps) {
  const { user } = useAuth();
  const { unreadCount } = useNotifications(user?.id);

  return (
    <Link
      to={to}
      aria-label={unreadCount > 0 ? `Notifications, ${unreadCount} unread` : 'Notifications'}
      className="focus-ring relative flex h-9 w-9 shrink-0 items-center justify-center rounded-md text-content-secondary transition-colors hover:bg-surface-sunken hover:text-content-primary"
    >
      <BellIcon className="h-5 w-5" />
      {unreadCount > 0 && (
        <span
          aria-hidden="true"
          className="absolute right-1 top-1 flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-danger-600 px-1 text-[10px] font-semibold leading-none text-white"
        >
          {unreadCount > 9 ? '9+' : unreadCount}
        </span>
      )}
    </Link>
  );
}
