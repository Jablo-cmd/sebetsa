import { describe, it, expect } from 'vitest';
import { USER_ROLES } from '@/features/auth/types/auth.types';
import {
  hasPermission,
  hasAnyPermission,
  hasAllPermissions,
  can,
} from '@/features/rbac/utils/permissionHelpers';

describe('hasPermission', () => {
  it('grants the self-service baseline to every role, including a null role', () => {
    for (const role of [...USER_ROLES, null]) {
      expect(hasPermission(role, 'profile.view_own')).toBe(true);
      expect(hasPermission(role, 'profile.update_own')).toBe(true);
    }
  });

  it('grants elevated permissions only to roles that carry them', () => {
    expect(hasPermission('organization_administrator', 'organization.manage')).toBe(true);
    expect(hasPermission('employee', 'organization.manage')).toBe(false);
  });

  it('denies every non-baseline permission for a null role', () => {
    expect(hasPermission(null, 'organization.view')).toBe(false);
    expect(hasPermission(null, 'tenant.switch')).toBe(false);
  });

  it('grants tenant.switch only to the platform-level role', () => {
    expect(hasPermission('platform_administrator', 'tenant.switch')).toBe(true);
    expect(hasPermission('organization_administrator', 'tenant.switch')).toBe(false);
    expect(hasPermission('employee', 'tenant.switch')).toBe(false);
  });

  it('rejects an out-of-catalogue permission at the type level', () => {
    // @ts-expect-error — intentionally probing an out-of-catalogue permission
    expect(hasPermission('platform_administrator', 'finance.view')).toBe(false);
  });
});

describe('hasAnyPermission / hasAllPermissions', () => {
  it('hasAnyPermission is true if at least one permission matches', () => {
    expect(hasAnyPermission('employee', ['organization.manage', 'attendance.view'])).toBe(true);
  });

  it('hasAnyPermission is false if none match', () => {
    expect(hasAnyPermission('client_user', ['organization.manage', 'tenant.switch'])).toBe(false);
  });

  it('hasAllPermissions requires every permission to match', () => {
    expect(hasAllPermissions('organization_administrator', ['organization.view', 'organization.manage'])).toBe(true);
    expect(hasAllPermissions('employee', ['organization.view', 'organization.manage'])).toBe(false);
  });
});

describe('can', () => {
  it('is an alias for hasPermission', () => {
    expect(can('organization_administrator', 'organization.manage')).toBe(
      hasPermission('organization_administrator', 'organization.manage'),
    );
    expect(can('employee', 'organization.manage')).toBe(hasPermission('employee', 'organization.manage'));
  });
});
