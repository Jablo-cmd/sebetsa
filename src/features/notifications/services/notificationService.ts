import { supabase } from '@/lib/supabase';
import type { NotificationRow } from '@/lib/dbTypes';
import type { Notification } from '@/features/notifications/types/notification.types';

function toNotification(row: NotificationRow): Notification {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    recipientProfileId: row.recipient_profile_id,
    type: row.type,
    title: row.title,
    body: row.body,
    relatedEntityTable: row.related_entity_table,
    relatedEntityId: row.related_entity_id,
    linkPath: row.link_path,
    isRead: row.read_at !== null,
    createdAt: row.created_at,
  };
}

/** The current user's notifications, most recent first. RLS (notifications_select_own) independently enforces that only the caller's own rows are ever returned — this filter is for query efficiency, not the actual security boundary. */
async function getMyNotifications(recipientProfileId: string): Promise<Notification[]> {
  const { data, error } = await supabase
    .from('notifications')
    .select('*')
    .eq('recipient_profile_id', recipientProfileId)
    .order('created_at', { ascending: false })
    .limit(50);
  if (error) throw error;
  return data.map(toNotification);
}

async function markRead(id: string): Promise<Notification> {
  const { data, error } = await supabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('id', id)
    .select('*')
    .single();
  if (error) throw error;
  return toNotification(data);
}

async function markAllRead(recipientProfileId: string): Promise<void> {
  const { error } = await supabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('recipient_profile_id', recipientProfileId)
    .is('read_at', null);
  if (error) throw error;
}

export const notificationService = { getMyNotifications, markRead, markAllRead };
