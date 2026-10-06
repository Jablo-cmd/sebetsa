import { Link } from 'react-router-dom';
import { AuthLayout } from '@/features/auth/components/AuthLayout';
import { ResetPasswordForm } from '@/features/auth/components/ResetPasswordForm';
import { useAuth } from '@/features/auth/context/authContext';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';

function InvalidResetLinkNotice() {
  return (
    <div className="flex flex-col gap-5">
      <div
        role="alert"
        className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
      >
        This password reset link is invalid or has expired.
      </div>
      <Link
        to="/forgot-password"
        className="focus-ring self-start rounded text-sm font-medium text-brand-600 dark:text-brand-300 hover:text-brand-700 hover:underline"
      >
        Request a new reset link
      </Link>
    </div>
  );
}

export function ResetPasswordPage() {
  const { status } = useAuth();

  if (status === 'initializing') {
    return <FullScreenSpinner label="Verifying your reset link…" />;
  }

  return (
    <AuthLayout title="Set a new password" subtitle="Choose a new password for your account.">
      {status === 'authenticated' ? <ResetPasswordForm /> : <InvalidResetLinkNotice />}
    </AuthLayout>
  );
}
