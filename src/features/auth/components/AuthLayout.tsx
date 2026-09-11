import type { ReactNode } from 'react';
import { Logo } from '@/components/ui/Logo';
import { ThemeToggle } from '@/components/ui/ThemeToggle';

export interface AuthLayoutProps {
  eyebrow?: string;
  title: string;
  subtitle?: string;
  children: ReactNode;
}

/** Shared chrome for every unauthenticated auth screen (login, forgot/reset password, verify email). */
export function AuthLayout({ eyebrow = 'Secure sign in', title, subtitle, children }: AuthLayoutProps) {
  const year = new Date().getFullYear();

  return (
    <div className="relative flex min-h-dvh flex-col items-center justify-center gap-8 overflow-y-auto bg-surface-sunken px-4 py-10">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>

      <div className="flex flex-col items-center gap-2 text-center">
        <Logo />
        <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-content-tertiary">
          Workforce Operations Platform
        </p>
      </div>

      <div className="w-full max-w-sm rounded-card border border-border bg-surface-raised p-6 shadow-card sm:p-8 dark:shadow-card-dark">
        <header className="mb-6">
          <p className="text-xs font-semibold uppercase tracking-wide text-brand-600 dark:text-brand-300">
            {eyebrow}
          </p>
          <h2 className="mt-1 text-xl font-bold text-content-primary sm:text-2xl">{title}</h2>
          {subtitle && <p className="mt-1.5 text-sm text-content-secondary">{subtitle}</p>}
        </header>

        {children}
      </div>

      <div className="flex flex-col items-center gap-1 text-center">
        <p className="text-[11px] text-content-tertiary">© {year} Sebetsa. All rights reserved.</p>
      </div>
    </div>
  );
}
