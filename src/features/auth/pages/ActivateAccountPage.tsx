import { Link } from 'react-router-dom';
import { AuthLayout } from '@/features/auth/components/AuthLayout';
import { ActivateAccountForm } from '@/features/auth/components/ActivateAccountForm';
import { useAuth } from '@/features/auth/context/authContext';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';

function InvalidInvitationNotice() {
  return (
    <div className="flex flex-col gap-5">
      <div
        role="alert"
        className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
      >
        This invitation link is invalid or has expired.
      </div>
      <Link
        to="/login"
        className="focus-ring self-start rounded text-sm font-medium text-brand-600 hover:text-brand-700 hover:underline"
      >
        Go to sign in
      </Link>
    </div>
  );
}

export function ActivateAccountPage() {
  const { status } = useAuth();

  if (status === 'initializing') {
    return <FullScreenSpinner label="Verifying your invitation…" />;
  }

  return (
    <AuthLayout eyebrow="Account activation" title="Activate your account" subtitle="Set a password to access your account.">
      {status === 'authenticated' ? <ActivateAccountForm /> : <InvalidInvitationNotice />}
    </AuthLayout>
  );
}
