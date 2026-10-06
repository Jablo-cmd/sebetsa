import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { PasswordField } from '@/components/ui/PasswordField';
import { Checkbox } from '@/components/ui/Checkbox';
import { useAuth } from '@/features/auth/context/authContext';
import { getAuthErrorMessage } from '@/features/auth/utils/authErrors';
import {
  loginSchema,
  loginDefaultValues,
  type LoginFormValues,
} from '@/features/auth/schemas/loginSchema';

interface LocationState {
  from?: { pathname?: string };
  justReset?: boolean;
  justActivated?: boolean;
}

export function LoginForm() {
  const { signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [submitError, setSubmitError] = useState<string | null>(null);

  const state = location.state as LocationState | null;
  const justReset = Boolean(state?.justReset);
  const justActivated = Boolean(state?.justActivated);

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: loginDefaultValues,
    mode: 'onBlur',
  });

  const onValid = async (values: LoginFormValues) => {
    setSubmitError(null);
    try {
      await signIn(values.email, values.password, values.rememberMe);
      navigate(state?.from?.pathname ?? '/', { replace: true });
    } catch (error) {
      setSubmitError(getAuthErrorMessage(error));
    }
  };

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

      {justReset && !submitError && (
        <div
          role="status"
          className="rounded-lg border border-success-500/30 bg-success-500/10 px-3.5 py-2.5 text-sm font-medium text-success-500"
        >
          Your password has been updated. Please sign in.
        </div>
      )}

      {justActivated && !submitError && (
        <div
          role="status"
          className="rounded-lg border border-success-500/30 bg-success-500/10 px-3.5 py-2.5 text-sm font-medium text-success-500"
        >
          Your account is now active. Please sign in.
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

      <div>
        <div className="mb-1.5 flex items-baseline justify-between">
          <label htmlFor="password" className="text-sm font-medium text-content-primary">
            Password{' '}
            <span className="text-danger-600" aria-hidden="true">
              *
            </span>
          </label>
          <Link
            to="/forgot-password"
            className="focus-ring rounded text-sm font-medium text-brand-600 hover:text-brand-700 hover:underline"
          >
            Forgot password?
          </Link>
        </div>
        <PasswordField
          id="password"
          autoComplete="current-password"
          placeholder="Enter your password"
          required
          error={errors.password?.message}
          {...register('password')}
        />
      </div>

      <Checkbox label="Remember me" {...register('rememberMe')} />

      <Button type="submit" isLoading={isSubmitting}>
        {isSubmitting ? 'Signing in…' : 'Sign in'}
      </Button>
    </form>
  );
}
