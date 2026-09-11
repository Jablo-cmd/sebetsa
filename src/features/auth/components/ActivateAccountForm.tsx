import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button } from '@/components/ui/Button';
import { PasswordField } from '@/components/ui/PasswordField';
import { useAuth } from '@/features/auth/context/authContext';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { resetPasswordSchema, resetPasswordDefaultValues, type ResetPasswordFormValues } from '@/features/auth/schemas/resetPasswordSchema';

/**
 * Sets a password from the temporary Supabase session an invite/recovery
 * link establishes (see AuthProvider's PASSWORD_RECOVERY handling), then
 * signs the user out so they land on /login and sign in normally.
 */
export function ActivateAccountForm() {
  const { updatePassword, signOut } = useAuth();
  const [submitError, setSubmitError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ResetPasswordFormValues>({
    resolver: zodResolver(resetPasswordSchema),
    defaultValues: resetPasswordDefaultValues,
    mode: 'onBlur',
  });

  const onValid = async (values: ResetPasswordFormValues) => {
    setSubmitError(null);
    try {
      await updatePassword(values.password);
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to set your password.'));
      return;
    }
    await signOut({ redirectState: { justActivated: true } });
  };

  return (
    <form noValidate onSubmit={handleSubmit(onValid)} className="flex flex-col gap-5">
      <p className="text-sm text-content-secondary">Set a password to activate your account.</p>

      {submitError && (
        <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">
          {submitError}
        </div>
      )}

      <PasswordField
        id="new-password"
        label="Choose a password"
        autoComplete="new-password"
        placeholder="Enter a password"
        hint="Must be at least 8 characters."
        required
        error={errors.password?.message}
        {...register('password')}
      />

      <PasswordField
        id="confirm-new-password"
        label="Confirm password"
        autoComplete="new-password"
        placeholder="Re-enter your password"
        required
        error={errors.confirmPassword?.message}
        {...register('confirmPassword')}
      />

      <Button type="submit" isLoading={isSubmitting}>
        {isSubmitting ? 'Activating…' : 'Activate my account'}
      </Button>
    </form>
  );
}
