import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { Checkbox } from '@/components/ui/Checkbox';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { useToast } from '@/components/ui/toast/useToast';
import { useAuth } from '@/features/auth/context/authContext';
import {
  notificationPreferenceService,
  type NotificationPreferences,
} from '@/features/notifications/services/notificationPreferenceService';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** Every IANA zone this browser knows; falls back to a short list on very old engines. */
const TIME_ZONES: string[] = (() => {
  try {
    return (Intl as unknown as { supportedValuesOf: (key: string) => string[] }).supportedValuesOf('timeZone');
  } catch {
    return ['UTC', 'Africa/Johannesburg', 'Europe/London', 'America/New_York', 'Asia/Kolkata', 'Australia/Sydney'];
  }
})();

function deviceZone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  } catch {
    return 'UTC';
  }
}

export function NotificationSettingsPage() {
  const { user } = useAuth();
  const { showToast } = useToast();
  const [prefs, setPrefs] = useState<NotificationPreferences | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!user?.id) return;
    let cancelled = false;
    notificationPreferenceService
      .getMyPreferences(user.id)
      .then((next) => {
        if (!cancelled) setPrefs(next);
      })
      .catch((err) => {
        if (!cancelled) setError(getDbErrorMessage(err, 'Failed to load your preferences.'));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [user?.id]);

  const handleSave = async () => {
    if (!user?.id || !prefs) return;
    setSaving(true);
    setError(null);
    try {
      const saved = await notificationPreferenceService.saveMyPreferences(user.id, prefs);
      setPrefs(saved);
      showToast('Notification preferences saved.', { variant: 'success' });
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to save.'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Notification preferences"
        description="In-app notifications are always on. Choose which of them are also sent to you on other channels."
      />
      <ErrorAlert message={error} />

      {isLoading || !prefs ? (
        <LoadingBlock label="Loading preferences…" />
      ) : (
        <div className="flex max-w-xl flex-col gap-6">
          <fieldset className="flex flex-col gap-3 rounded-card border border-border bg-surface-raised p-4">
            <legend className="px-1 text-sm font-semibold text-content-primary">Channels</legend>
            <Checkbox
              label="Email"
              checked={prefs.emailEnabled}
              onChange={(e) => setPrefs({ ...prefs, emailEnabled: e.target.checked })}
            />
            <Checkbox
              label="SMS"
              checked={prefs.smsEnabled}
              onChange={(e) => setPrefs({ ...prefs, smsEnabled: e.target.checked })}
            />
            <Checkbox
              label="WhatsApp"
              checked={prefs.whatsappEnabled}
              onChange={(e) => setPrefs({ ...prefs, whatsappEnabled: e.target.checked })}
            />
            <p className="text-xs text-content-tertiary">
              A channel only delivers if your profile has the matching email address or phone number and a delivery
              provider has been configured for your organisation's deployment. Until then, messages still reach you
              in-app.
            </p>
          </fieldset>

          <fieldset className="flex flex-col gap-3 rounded-card border border-border bg-surface-raised p-4">
            <legend className="px-1 text-sm font-semibold text-content-primary">Quiet hours (optional)</legend>
            <p className="text-xs text-content-tertiary">
              External deliveries created during this window are held until it ends. In-app notifications are never
              delayed.
            </p>
            <div className="flex gap-3">
              <label className="flex flex-col gap-1 text-sm text-content-primary">
                From
                <input
                  type="time"
                  className="h-11 rounded-md border border-border-strong bg-surface-raised px-3 text-sm"
                  value={prefs.quietHoursStart ?? ''}
                  onChange={(e) => setPrefs({ ...prefs, quietHoursStart: e.target.value || null })}
                />
              </label>
              <label className="flex flex-col gap-1 text-sm text-content-primary">
                To
                <input
                  type="time"
                  className="h-11 rounded-md border border-border-strong bg-surface-raised px-3 text-sm"
                  value={prefs.quietHoursEnd ?? ''}
                  onChange={(e) => setPrefs({ ...prefs, quietHoursEnd: e.target.value || null })}
                />
              </label>
            </div>
            <label className="flex max-w-sm flex-col gap-1 text-sm text-content-primary">
              Time zone
              <select
                className="h-11 rounded-md border border-border-strong bg-surface-raised px-3 text-sm"
                value={prefs.timeZone ?? ''}
                onChange={(e) => setPrefs({ ...prefs, timeZone: e.target.value || null })}
              >
                <option value="">My organisation's time zone</option>
                {TIME_ZONES.map((zone) => (
                  <option key={zone} value={zone}>
                    {zone}
                  </option>
                ))}
              </select>
              <span className="text-xs text-content-tertiary">
                Quiet hours follow this zone, including daylight saving. Your device is currently set to {deviceZone()}.
              </span>
            </label>
          </fieldset>

          <div className="w-40">
            <Button type="button" onClick={() => void handleSave()} isLoading={saving}>
              Save preferences
            </Button>
          </div>
        </div>
      )}
    </PageContainer>
  );
}
