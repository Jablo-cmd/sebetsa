import { describe, it, expect } from 'vitest';
import { USER_ROLES } from '@/features/auth/types/auth.types';
import { isValidRole, hasRole, isAtLeast } from '@/features/rbac/utils/roleHelpers';

describe('isValidRole', () => {
  it('accepts every canonical role slug', () => {
    for (const role of USER_ROLES) {
      expect(isValidRole(role)).toBe(true);
    }
  });

  it('rejects unknown strings and non-string values', () => {
    expect(isValidRole('wizard')).toBe(false);
    expect(isValidRole(42)).toBe(false);
    expect(isValidRole(null)).toBe(false);
    expect(isValidRole(undefined)).toBe(false);
  });
});

describe('hasRole', () => {
  it('matches when role is in the allowed list', () => {
    expect(hasRole('organization_administrator', 'organization_administrator', 'operations_manager')).toBe(true);
  });

  it('does not match when role is absent from the allowed list', () => {
    expect(hasRole('employee', 'organization_administrator', 'operations_manager')).toBe(false);
  });

  it('never matches a null or undefined role', () => {
    expect(hasRole(null, 'organization_administrator')).toBe(false);
    expect(hasRole(undefined, 'organization_administrator')).toBe(false);
  });
});

describe('isAtLeast', () => {
  it('is true when role outranks the threshold', () => {
    expect(isAtLeast('organization_administrator', 'employee')).toBe(true);
  });

  it('is true when role exactly matches the threshold', () => {
    expect(isAtLeast('employee', 'employee')).toBe(true);
  });

  it('is false when role is junior to the threshold', () => {
    expect(isAtLeast('client_user', 'employee')).toBe(false);
  });

  it('is false for a null or undefined role regardless of threshold', () => {
    expect(isAtLeast(null, 'client_user')).toBe(false);
    expect(isAtLeast(undefined, 'client_user')).toBe(false);
  });

  it('places platform_administrator at least as senior as every other role', () => {
    for (const role of USER_ROLES) {
      expect(isAtLeast('platform_administrator', role)).toBe(true);
    }
  });

  it('places client_user below every other role', () => {
    for (const role of USER_ROLES) {
      if (role === 'client_user') continue;
      expect(isAtLeast('client_user', role)).toBe(false);
    }
  });
});
