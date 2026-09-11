import { supabase } from '@/lib/supabase';
import type { Factor, AuthenticatorAssuranceLevels } from '@supabase/supabase-js';

export interface EnrollmentResult {
  factorId: string;
  /** `data:image/svg+xml;utf-8,<svg>` — ready to drop straight into an <img src>. */
  qrCodeDataUri: string;
  /** Shown alongside the QR code for a user who can't scan it (manual entry into their authenticator app). */
  secret: string;
}

/**
 * Deliberately reads `session.user.factors` off the already-in-memory
 * session (via getSession(), which is purely local — no network request)
 * rather than calling `supabase.auth.mfa.listFactors()`, which internally
 * calls `getUser()` and does a real round trip to GoTrue's `/user`
 * endpoint every time. This is mounted on every dashboard page
 * (MfaRequiredBanner) and on My Profile (MfaEnrollmentCard), so making it
 * network-free avoids turning every protected page load into an extra
 * auth round trip. Same filtering `supabase.auth.mfa.listFactors()`
 * itself applies (factor_type totp, status verified).
 */
async function listFactors(): Promise<Factor[]> {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  const factors = data.session?.user.factors ?? [];
  return factors.filter((factor) => factor.factor_type === 'totp' && factor.status === 'verified');
}

/** Starts TOTP enrollment. The returned factor is `unverified` until verifyEnrollment() succeeds — listFactors() won't count it as active MFA until then. */
async function startEnrollment(): Promise<EnrollmentResult> {
  const { data, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', issuer: 'Sebetsa' });
  if (error) throw error;
  // enroll()'s return type is a { type: 'totp' } | { type: 'phone' } union
  // even though we only ever request 'totp' — narrow explicitly rather
  // than asserting, so a real API-response mismatch surfaces as a thrown
  // error instead of a silently wrong `.totp` access.
  if (data.type !== 'totp') {
    throw new Error('Expected a TOTP enrollment response.');
  }
  return {
    factorId: data.id,
    qrCodeDataUri: `data:image/svg+xml;utf-8,${encodeURIComponent(data.totp.qr_code)}`,
    secret: data.totp.secret,
  };
}

/** Confirms enrollment with the 6-digit code from the user's authenticator app — promotes the session to aal2 on success. */
async function verifyEnrollment(factorId: string, code: string): Promise<void> {
  const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({ factorId });
  if (challengeError) throw challengeError;
  const { error: verifyError } = await supabase.auth.mfa.verify({ factorId, challengeId: challenge.id, code });
  if (verifyError) throw verifyError;
}

/**
 * Abandons an in-progress (unverified) enrollment, or removes an
 * already-verified factor. Supabase itself requires aal2 to unenroll a
 * verified factor — a user can't turn off MFA without proving they still
 * have it.
 *
 * Explicitly refreshes the session afterward — unlike verify() (which the
 * SDK documents as promoting the session to aal2 itself), unenroll()
 * removes the factor server-side but does NOT update the already-cached
 * local session's `user.factors`, which is exactly what listFactors()
 * reads (deliberately, to stay network-free — see its own comment). Without
 * this, the UI would keep reporting the just-removed factor as still
 * verified until the next unrelated token refresh happened to occur.
 * Confirmed this was a real bug, not a hypothetical, via a live check
 * against a real factor.
 */
async function unenroll(factorId: string): Promise<void> {
  const { error } = await supabase.auth.mfa.unenroll({ factorId });
  if (error) throw error;
  await supabase.auth.refreshSession();
}

/** One-shot challenge+verify for the login-time step-up screen (MfaChallengePage) — the user already has a verified factor, this just proves they still control it this session. */
async function challengeAndVerify(factorId: string, code: string): Promise<void> {
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
  if (error) throw error;
}

async function getAssuranceLevel(): Promise<{ currentLevel: AuthenticatorAssuranceLevels | null; nextLevel: AuthenticatorAssuranceLevels | null }> {
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (error) throw error;
  return { currentLevel: data.currentLevel, nextLevel: data.nextLevel };
}

export const mfaService = {
  listFactors,
  startEnrollment,
  verifyEnrollment,
  unenroll,
  challengeAndVerify,
  getAssuranceLevel,
};
