import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useAuth } from '@/features/auth/context/authContext';
import { getAuthErrorMessage } from '@/features/auth/utils/authErrors';
import {
  forgotPasswordSchema,
  forgotPasswordDefaultValues,
  type ForgotPasswordFormValues,
} from '@/features/auth/schemas/forgotPasswordSchema';

export function ForgotPasswordForm() {
  const { requestPasswordReset } = useAuth();
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [isSent, setIsSent] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ForgotPasswordFormValues>({
    resolver: zodResolver(forgotPasswordSchema),
    defaultValues: forgotPasswordDefaultValues,
    mode: 'onBlur',
  });

  const onValid = async (values: ForgotPasswordFormValues) => {
    setSubmitError(null);
    try {
      await requestPasswordReset(values.email);
      setIsSent(true);
    } catch (error) {
      setSubmitError(getAuthErrorMessage(error));
    }
  };

  if (isSent) {
    return (
      <div className="flex flex-col gap-5">
        <div
          role="status"
          className="rounded-lg border border-success-500/30 bg-success-500/10 px-3.5 py-2.5 text-sm font-medium text-success-500"
        >
          If an account exists for that email address, we&apos;ve sent a link to reset your
          password. Please check your inbox.
        </div>
        <Link
          to="/login"
          className="focus-ring self-start rounded text-sm font-medium text-brand-600 dark:text-brand-300 hover:text-brand-700 hover:underline"
        >
          Back to sign in
        </Link>
      </div>
    );
  }

  return (
    <form noValidate onSubmit={handleSubmit(onValid)} className="flex flex-col gap-5">
      {submitError && (
        <div
          role="alert"
          className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
        >
          {submitError}
        </div>
      )}

      <TextField
        label="Email address"
        type="email"
        autoComplete="username"
        placeholder="you@company.example"
        required
        error={errors.email?.message}
        {...register('email')}
      />

      <Button type="submit" isLoading={isSubmitting}>
        {isSubmitting ? 'Sending…' : 'Send reset link'}
      </Button>

      <Link
        to="/login"
        className="focus-ring self-center rounded text-sm font-medium text-content-secondary hover:text-content-primary hover:underline"
      >
        Back to sign in
      </Link>
    </form>
  );
}
