import { describe, it, expect } from 'vitest';
import { isMfaRequiredForRole } from '@/features/rbac/constants/mfaRequiredRoles';

describe('isMfaRequiredForRole', () => {
  it('requires MFA for roles that manage other users\' accounts', () => {
    expect(isMfaRequiredForRole('organization_administrator')).toBe(true);
    expect(isMfaRequiredForRole('hr_user')).toBe(true);
  });

  it('requires MFA for the platform-wide admin role', () => {
    expect(isMfaRequiredForRole('platform_administrator')).toBe(true);
  });

  it('does not require MFA for an employee (no account-management power)', () => {
    expect(isMfaRequiredForRole('employee')).toBe(false);
  });

  it('does not require MFA for a client_user', () => {
    expect(isMfaRequiredForRole('client_user')).toBe(false);
  });

  it('does not require MFA for a site_manager (scheduling/attendance, not account management)', () => {
    expect(isMfaRequiredForRole('site_manager')).toBe(false);
  });

  it('returns false for a null role', () => {
    expect(isMfaRequiredForRole(null)).toBe(false);
  });
});
