import { supabase } from '@/lib/supabase';
import type { Database } from '@/lib/database.types';

type NotificationPreferenceRow = Database['public']['Tables']['notification_preferences']['Row'];

export interface NotificationPreferences {
  emailEnabled: boolean;
  smsEnabled: boolean;
  whatsappEnabled: boolean;
  quietHoursStart: string | null;
  quietHoursEnd: string | null;
  /** IANA zone the quiet hours are evaluated in; null = the organisation's zone. */
  timeZone: string | null;
}

const DEFAULTS: NotificationPreferences = {
  emailEnabled: false,
  smsEnabled: false,
  whatsappEnabled: false,
  quietHoursStart: null,
  quietHoursEnd: null,
  timeZone: null,
};

function toPreferences(row: NotificationPreferenceRow): NotificationPreferences {
  return {
    emailEnabled: row.email_enabled,
    smsEnabled: row.sms_enabled,
    whatsappEnabled: row.whatsapp_enabled,
    quietHoursStart: row.quiet_hours_start?.slice(0, 5) ?? null,
    quietHoursEnd: row.quiet_hours_end?.slice(0, 5) ?? null,
    timeZone: row.time_zone,
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
        time_zone: prefs.timeZone,
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
