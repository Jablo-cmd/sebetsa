import { AuthLayout } from '@/features/auth/components/AuthLayout';
import { LoginForm } from '@/features/auth/components/LoginForm';

export function LoginPage() {
  return (
    <AuthLayout
      title="Sign in to your account"
      subtitle="Enter your credentials to access your Sebetsa workspace."
    >
      <LoginForm />
    </AuthLayout>
  );
}
