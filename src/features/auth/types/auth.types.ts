/**
 * Role catalogue. Slugs are the expected values of the `role` claim in
 * `app_metadata` and must match `public.user_role` in
 * supabase/migrations/20260911100300_user_role_management.sql — keep both
 * in sync.
 */
export const USER_ROLES = [
  'platform_administrator',
  'organization_administrator',
  'operations_manager',
  'regional_manager',
  'site_manager',
  'supervisor',
  'hr_user',
  'employee',
  'client_user',
] as const;

export type UserRole = (typeof USER_ROLES)[number];

export type AuthStatus = 'initializing' | 'authenticated' | 'unauthenticated';

export interface AuthenticatedUser {
  id: string;
  email: string | null;
  emailVerified: boolean;
  /** Read from the JWT `role` claim (RBAC spec §4) — Supabase always includes `app_metadata` in the token, so this is populated as soon as `app_metadata.role` is set (seed script, admin API call, or a token hook that recomputes it); null otherwise. */
  role: UserRole | null;
  /** Read from the JWT `tenant_id` claim (RBAC spec §4); same populate-on-app_metadata mechanism as `role`. */
  tenantId: string | null;
}

export interface SignOutOptions {
  /** Extra router state to hand to the /login screen we redirect to (e.g. a one-time success banner). */
  redirectState?: Record<string, unknown>;
}

export interface AuthContextValue {
  status: AuthStatus;
  user: AuthenticatedUser | null;
  /** True once a signed-in user with a verified MFA factor still needs to complete this session's step-up challenge (aal1, but aal2 available). Null while unknown/not applicable — never a false negative used to hide the challenge screen. See ProtectedRoute. */
  mfaChallengePending: boolean | null;
  /** True once the user has at least one verified MFA factor (regardless of whether this session has stepped up yet). Computed alongside mfaChallengePending from the same getAssuranceLevel() call — read this in MfaRequiredBanner instead of re-fetching, so the banner never flashes in after first paint. */
  hasMfaEnabled: boolean | null;
  signIn: (email: string, password: string, rememberMe: boolean) => Promise<void>;
  signOut: (options?: SignOutOptions) => Promise<void>;
  requestPasswordReset: (email: string) => Promise<void>;
  updatePassword: (newPassword: string) => Promise<void>;
  resendVerificationEmail: () => Promise<void>;
  /** Re-derives mfaChallengePending — call after a successful MFA challenge (see MfaChallengePage). */
  refreshMfaChallengeStatus: () => Promise<void>;
  hasRole: (...roles: UserRole[]) => boolean;
}
