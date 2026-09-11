import { cn } from '@/lib/cn';

export interface LogoProps {
  variant?: 'default' | 'inverse';
  showWordmark?: boolean;
  className?: string;
}

/**
 * Sebetsa mark: a rounded tile with an "S" monogram — the platform's
 * multi-tenant workforce/operations identity.
 */
export function Logo({ variant = 'default', showWordmark = true, className }: LogoProps) {
  const wordmarkClass = variant === 'inverse' ? 'text-white' : 'text-content-primary';

  return (
    <div className={cn('flex items-center gap-2.5', className)}>
      <svg width="32" height="32" viewBox="0 0 32 32" fill="none" aria-hidden="true">
        <rect width="32" height="32" rx="6" className="fill-brand-600" />
        <path
          d="M21 12.5c0-1.5-1.8-2.5-5-2.5s-5 1-5 2.5 1.8 2.2 5 2.7 5 1.4 5 3-1.8 2.8-5 2.8-5-1.1-5-2.8"
          stroke="white"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>

      {showWordmark && (
        <span className={cn('text-lg font-bold tracking-tight', wordmarkClass)}>Sebetsa</span>
      )}
    </div>
  );
}
