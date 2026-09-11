import { supabase } from '@/lib/supabase';
import type { Database } from '@/lib/database.types';

type NotificationPreferenceRow = Database['public']['Tables']['notification_preferences']['Row'];

export interface NotificationPreferences {
  emailEnabled: boolean;
  smsEnabled: boolean;
  whatsappEnabled: boolean;
  quietHoursStart: string | null;
  quietHoursEnd: string | null;
}

const DEFAULTS: NotificationPreferences = {
  emailEnabled: false,
  smsEnabled: false,
  whatsappEnabled: false,
  quietHoursStart: null,
  quietHoursEnd: null,
};

function toPreferences(row: NotificationPreferenceRow): NotificationPreferences {
  return {
    emailEnabled: row.email_enabled,
    smsEnabled: row.sms_enabled,
    whatsappEnabled: row.whatsapp_enabled,
    quietHoursStart: row.quiet_hours_start,
    quietHoursEnd: row.quiet_hours_end,
  };
}

/** The caller's own preferences. Returns sensible defaults (all external channels off) when no row exists yet. */
async function getMyPreferences(profileId: string): Promise<NotificationPreferences> {
  const { data, error } = await supabase
    .from('notification_preferences')
    .select('*')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (error) throw error;
  return data ? toPreferences(data) : { ...DEFAULTS };
}

async function saveMyPreferences(profileId: string, prefs: NotificationPreferences): Promise<NotificationPreferences> {
  const { data, error } = await supabase
    .from('notification_preferences')
    .upsert(
      {
        profile_id: profileId,
        email_enabled: prefs.emailEnabled,
        sms_enabled: prefs.smsEnabled,
        whatsapp_enabled: prefs.whatsappEnabled,
        quiet_hours_start: prefs.quietHoursStart,
        quiet_hours_end: prefs.quietHoursEnd,
      },
      { onConflict: 'profile_id' },
    )
    .select('*')
    .single();
  if (error) throw error;
  return toPreferences(data);
}

export const notificationPreferenceService = {
  getMyPreferences,
  saveMyPreferences,
};
