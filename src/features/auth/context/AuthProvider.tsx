import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { useNavigate } from 'react-router-dom';
import { supabase, setAuthPersistence } from '@/lib/supabase';
import { isCurrentPath } from '@/lib/appUrl';
import { authService } from '@/features/auth/services/authService';
import { mfaService } from '@/features/mfa/services/mfaService';
import { toAuthenticatedUser } from '@/features/auth/utils/toAuthenticatedUser';
import { AuthContext } from '@/features/auth/context/authContext';
import type {
  AuthContextValue,
  AuthStatus,
  AuthenticatedUser,
  SignOutOptions,
  UserRole,
} from '@/features/auth/types/auth.types';

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>('initializing');
  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  // Both null = not yet determined (still checking, or no session at all).
  // ProtectedRoute blocks on mfaChallengePending === null (see its own
  // comment for why: this resolves in well under a frame — a local,
  // no-network check — so blocking briefly there is cheaper than letting
  // MfaRequiredBanner pop in after first paint and shift the page).
  // hasMfaEnabled is derived from the exact same getAssuranceLevel() call,
  // computed together so MfaRequiredBanner reads already-resolved context
  // state instead of running its own separate, later-resolving fetch.
  const [mfaChallengePending, setMfaChallengePending] = useState<boolean | null>(null);
  const [hasMfaEnabled, setHasMfaEnabled] = useState<boolean | null>(null);
  const navigate = useNavigate();

  const applySession = useCallback((session: Session | null) => {
    if (session?.user) {
      setUser(toAuthenticatedUser(session.user));
      setStatus('authenticated');
      // A verified TOTP factor exists (nextLevel aal2) but this specific
      // session hasn't completed the step-up challenge yet (currentLevel
      // still aal1) — e.g. a fresh password sign-in. Recomputed on every
      // session change, including right after MfaChallengePage's own
      // challengeAndVerify() call promotes the session to aal2.
      mfaService
        .getAssuranceLevel()
        .then(({ currentLevel, nextLevel }) => {
          setHasMfaEnabled(nextLevel === 'aal2');
          setMfaChallengePending(nextLevel === 'aal2' && currentLevel !== nextLevel);
        })
        .catch(() => {
          setHasMfaEnabled(false);
          setMfaChallengePending(false);
        });
    } else {
      setUser(null);
      setStatus('unauthenticated');
      setMfaChallengePending(null);
      setHasMfaEnabled(null);
    }
  }, []);

  useEffect(() => {
    let isMounted = true;

    authService
      .getSession()
      .then((session) => {
        if (isMounted) applySession(session);
      })
      .catch(() => {
        if (isMounted) applySession(null);
      });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (!isMounted) return;
      applySession(session);
      if (event === 'PASSWORD_RECOVERY') {
        // Account activation (/activate-account, the landing page for an
        // invite link) reuses the same Supabase recovery-session mechanism
        // as "forgot password" (/reset-password). Only redirect to the
        // reset page if the browser isn't already on the activation page
        // the invite link pointed at.
        if (!isCurrentPath('/activate-account')) {
          navigate('/reset-password', { replace: true });
        }
      }
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, [applySession, navigate]);

  const signIn = useCallback(
    async (email: string, password: string, rememberMe: boolean) => {
      setAuthPersistence(rememberMe);
      const session = await authService.signInWithPassword(email, password);
      applySession(session);
    },
    [applySession],
  );

  const signOut = useCallback(
    async (options?: SignOutOptions) => {
      await authService.signOut();
      applySession(null);
      navigate('/login', { replace: true, state: options?.redirectState });
    },
    [applySession, navigate],
  );

  const requestPasswordReset = useCallback(
    (email: string) => authService.requestPasswordReset(email),
    [],
  );

  const updatePassword = useCallback(
    (newPassword: string) => authService.updatePassword(newPassword),
    [],
  );

  const resendVerificationEmail = useCallback(async () => {
    if (!user?.email) {
      throw new Error('No email address on file for this account.');
    }
    await authService.resendVerificationEmail(user.email);
  }, [user]);

  const hasRole = useCallback(
    (...roles: UserRole[]) => Boolean(user?.role && roles.includes(user.role)),
    [user],
  );

  /**
   * Called explicitly by MfaChallengePage right after challengeAndVerify()
   * succeeds — belt-and-suspenders alongside the onAuthStateChange
   * listener above (MFA verification does refresh the session/JWT, which
   * should already fire that listener on its own, but re-deriving this
   * directly here doesn't depend on that happening on any particular
   * timeline).
   */
  const refreshMfaChallengeStatus = useCallback(async () => {
    const { currentLevel, nextLevel } = await mfaService.getAssuranceLevel();
    setHasMfaEnabled(nextLevel === 'aal2');
    setMfaChallengePending(nextLevel === 'aal2' && currentLevel !== nextLevel);
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      user,
      mfaChallengePending,
      hasMfaEnabled,
      signIn,
      signOut,
      requestPasswordReset,
      updatePassword,
      resendVerificationEmail,
      refreshMfaChallengeStatus,
      hasRole,
    }),
    [
      status,
      user,
      mfaChallengePending,
      hasMfaEnabled,
      signIn,
      signOut,
      requestPasswordReset,
      updatePassword,
      resendVerificationEmail,
      refreshMfaChallengeStatus,
      hasRole,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
