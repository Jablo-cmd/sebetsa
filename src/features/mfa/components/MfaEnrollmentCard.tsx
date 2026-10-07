import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { useMfaFactors } from '@/features/mfa/hooks/useMfaFactors';
import { mfaService, type EnrollmentResult } from '@/features/mfa/services/mfaService';
import { getDbErrorMessage } from '@/lib/dbErrors';

/**
 * Self-service TOTP enrollment/removal — lives on My Profile. Works for
 * any signed-in user. For roles in mfaRequiredRoles.ts it is mandatory (the
 * database refuses them without aal2) and is also shown by MfaSetupPage.
 */
export interface MfaEnrollmentCardProps {
  /** Called once a factor has been verified (the session is then aal2). */
  onEnrolled?: () => void;
  /** False for roles that must keep MFA: the database refuses them without it, so removal would lock them out. */
  allowRemoval?: boolean;
}

export function MfaEnrollmentCard({ onEnrolled, allowRemoval = true }: MfaEnrollmentCardProps = {}) {
  const { verifiedFactor, isLoading, error, refetch } = useMfaFactors();
  const [enrollment, setEnrollment] = useState<EnrollmentResult | null>(null);
  const [code, setCode] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);
  const [isWorking, setIsWorking] = useState(false);

  const handleStartEnrollment = async () => {
    setActionError(null);
    setIsWorking(true);
    try {
      const result = await mfaService.startEnrollment();
      setEnrollment(result);
      setCode('');
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to start two-factor authentication setup.'));
    } finally {
      setIsWorking(false);
    }
  };

  const handleVerify = async () => {
    if (!enrollment) return;
    setActionError(null);
    setIsWorking(true);
    try {
      await mfaService.verifyEnrollment(enrollment.factorId, code);
      setEnrollment(null);
      setCode('');
      await refetch();
      onEnrolled?.();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'That code didn’t match — check your authenticator app and try again.'));
    } finally {
      setIsWorking(false);
    }
  };

  const handleCancelEnrollment = async () => {
    if (!enrollment) return;
    setIsWorking(true);
    try {
      await mfaService.unenroll(enrollment.factorId);
    } catch {
      // Best-effort cleanup — an abandoned unverified factor is harmless
      // (it never counts toward verifiedFactor), so a failure here doesn't
      // need to block the user from just walking away from setup.
    } finally {
      setEnrollment(null);
      setCode('');
      setIsWorking(false);
    }
  };

  const handleRemove = async () => {
    if (!verifiedFactor) return;
    setActionError(null);
    setIsWorking(true);
    try {
      await mfaService.unenroll(verifiedFactor.id);
      await refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to remove two-factor authentication.'));
    } finally {
      setIsWorking(false);
    }
  };

  if (isLoading) {
    return <LoadingBlock label="Loading two-factor authentication status…" />;
  }

  return (
    <section id="mfa-security" className="rounded-card border border-border bg-surface-raised p-5 shadow-card dark:shadow-card-dark sm:p-6">
      <h2 className="text-base font-semibold text-content-primary">Two-Factor Authentication</h2>
      <p className="mt-1 text-sm text-content-secondary">
        Adds a 6-digit code from an authenticator app (like Google Authenticator or Authy) on top of your password.
      </p>

      <ErrorAlert message={error ?? actionError} />

      {verifiedFactor ? (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <span className="inline-flex items-center rounded-full bg-success-500/10 px-2.5 py-1 text-xs font-medium text-success-500">
            Enabled
          </span>
          {allowRemoval ? (
            <div className="w-full sm:w-auto sm:min-w-[10rem]">
              <Button type="button" variant="secondary" isLoading={isWorking} onClick={() => void handleRemove()}>
                Remove two-factor authentication
              </Button>
            </div>
          ) : (
            <p className="text-sm text-content-secondary">Required for your role, so it cannot be removed here.</p>
          )}
        </div>
      ) : enrollment ? (
        <div className="mt-4 flex flex-col gap-4">
          <div className="flex flex-col items-start gap-4 sm:flex-row">
            <img src={enrollment.qrCodeDataUri} alt="Scan this QR code with your authenticator app" className="h-40 w-40 shrink-0 rounded-md border border-border bg-white p-2" />
            <div className="flex-1">
              <p className="text-sm text-content-secondary">
                Scan this QR code with your authenticator app, or enter this code manually:
              </p>
              <code className="mt-1.5 block break-all rounded-md bg-surface-sunken px-3 py-2 text-xs text-content-primary">{enrollment.secret}</code>
            </div>
          </div>

          <TextField
            label="Enter the 6-digit code from your app"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
          />

          <div className="flex flex-wrap gap-3">
            <div className="w-full sm:w-auto sm:min-w-[10rem]">
              <Button type="button" isLoading={isWorking} disabled={code.length !== 6} onClick={() => void handleVerify()}>
                Verify and enable
              </Button>
            </div>
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" disabled={isWorking} onClick={() => void handleCancelEnrollment()}>
                Cancel
              </Button>
            </div>
          </div>
        </div>
      ) : (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <span className="inline-flex items-center rounded-full bg-surface-sunken px-2.5 py-1 text-xs font-medium text-content-tertiary">
            Not enabled
          </span>
          <div className="w-full sm:w-auto sm:min-w-[12rem]">
            <Button type="button" isLoading={isWorking} onClick={() => void handleStartEnrollment()}>
              Set up two-factor authentication
            </Button>
          </div>
        </div>
      )}
    </section>
  );
}
