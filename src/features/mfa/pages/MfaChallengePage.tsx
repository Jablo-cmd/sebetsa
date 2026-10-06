import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { AuthLayout } from '@/features/auth/components/AuthLayout';
import { useAuth } from '@/features/auth/context/authContext';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { useMfaFactors } from '@/features/mfa/hooks/useMfaFactors';
import { mfaService } from '@/features/mfa/services/mfaService';
import { getDbErrorMessage } from '@/lib/dbErrors';

/**
 * The step-up screen ProtectedRoute sends a user to when they've signed in
 * with just a password but have a verified TOTP factor on file (session
 * is aal1, aal2 is available — see mfaChallengePending in AuthProvider).
 * Lives outside the protected route tree, same as /verify-email.
 */
export function MfaChallengePage() {
  const { status, mfaChallengePending, refreshMfaChallengeStatus, signOut } = useAuth();
  const { verifiedFactor, isLoading: isLoadingFactors } = useMfaFactors();
  const navigate = useNavigate();
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isVerifying, setIsVerifying] = useState(false);

  if (status === 'initializing' || mfaChallengePending === null) {
    return <FullScreenSpinner />;
  }

  if (status === 'unauthenticated' || mfaChallengePending === false) {
    return <Navigate to="/" replace />;
  }

  const handleVerify = async () => {
    if (!verifiedFactor) return;
    setError(null);
    setIsVerifying(true);
    try {
      await mfaService.challengeAndVerify(verifiedFactor.id, code);
      await refreshMfaChallengeStatus();
      navigate('/', { replace: true });
    } catch (err) {
      setError(getDbErrorMessage(err, 'That code didn’t match — check your authenticator app and try again.'));
      setCode('');
    } finally {
      setIsVerifying(false);
    }
  };

  return (
    <AuthLayout title="Verify it's you" subtitle="Enter the 6-digit code from your authenticator app.">
      <div className="flex flex-col gap-5">
        {error && (
          <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">
            {error}
          </div>
        )}

        <TextField
          label="Authentication code"
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={6}
          disabled={isLoadingFactors || !verifiedFactor}
          value={code}
          onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
        />

        <Button type="button" isLoading={isVerifying} disabled={code.length !== 6 || !verifiedFactor} onClick={() => void handleVerify()}>
          Verify
        </Button>

        <p className="text-center text-xs text-content-tertiary">
          Lost access to your authenticator app? Contact your organisation administrator.
        </p>

        <Button type="button" variant="ghost" onClick={() => void signOut()}>
          Sign out
        </Button>
      </div>
    </AuthLayout>
  );
}
