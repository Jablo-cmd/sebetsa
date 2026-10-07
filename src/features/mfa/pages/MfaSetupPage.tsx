import { Navigate } from 'react-router-dom';
import { AuthLayout } from '@/features/auth/components/AuthLayout';
import { useAuth } from '@/features/auth/context/authContext';
import { Button } from '@/components/ui/Button';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { MfaEnrollmentCard } from '@/features/mfa/components/MfaEnrollmentCard';
import { isMfaRequiredForRole } from '@/features/rbac/constants/mfaRequiredRoles';

/**
 * Forced enrolment for a role that must use MFA but has no verified factor.
 * The database refuses such a session every tenant-scoped read and write (it
 * is not aal2), so the normal app cannot load; this page needs nothing but
 * the auth session, which is why it lives outside ProtectedRoute/TenantGate.
 * After enrolment the page is reloaded so the profile and tenant are fetched
 * again with the new aal2 token.
 */
export function MfaSetupPage() {
  const { status, user, hasMfaEnabled, refreshMfaChallengeStatus, signOut } = useAuth();

  if (status === 'initializing' || (status === 'authenticated' && hasMfaEnabled === null)) {
    return <FullScreenSpinner />;
  }
  if (status === 'unauthenticated') return <Navigate to="/login" replace />;
  if (!isMfaRequiredForRole(user?.role ?? null) || hasMfaEnabled) return <Navigate to="/" replace />;

  const handleEnrolled = () => {
    void refreshMfaChallengeStatus().finally(() => window.location.assign('/dashboard'));
  };

  return (
    <AuthLayout eyebrow="Security" title="Set up two-factor authentication" subtitle="Your role requires it. Nothing in the app is available until it is set up.">
      <div className="flex flex-col gap-5">
        <MfaEnrollmentCard onEnrolled={handleEnrolled} allowRemoval={false} />
        <Button type="button" variant="ghost" onClick={() => void signOut()}>
          Sign out
        </Button>
      </div>
    </AuthLayout>
  );
}
