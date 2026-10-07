import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '@/features/auth/context/authContext';
import { isMfaRequiredForRole } from '@/features/rbac/constants/mfaRequiredRoles';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';

/** Gate for routes that require a signed-in, email-verified user who has completed any pending MFA step-up challenge. */
export function ProtectedRoute() {
  const { status, user, mfaChallengePending, hasMfaEnabled } = useAuth();
  const location = useLocation();

  if (status === 'initializing') {
    return <FullScreenSpinner label="Loading your session…" />;
  }

  if (status === 'unauthenticated') {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  if (user && !user.emailVerified) {
    return <Navigate to="/verify-email" replace />;
  }

  // mfaChallengePending starts null while AuthProvider resolves the assurance
  // level after a fresh sign-in (a local, no-network check). Waiting for it
  // here means the challenge / forced-enrolment redirects below happen before
  // the protected tree renders, instead of after a flash of the app.
  if (mfaChallengePending === null) {
    return <FullScreenSpinner label="Loading your session…" />;
  }

  if (mfaChallengePending) {
    return <Navigate to="/mfa-challenge" replace />;
  }

  // A role the database requires MFA for has no tenant access at all until it
  // is aal2, so without a factor the only useful place is enrolment.
  if (hasMfaEnabled === false && isMfaRequiredForRole(user?.role ?? null)) {
    return <Navigate to="/mfa-setup" replace />;
  }

  return <Outlet />;
}
