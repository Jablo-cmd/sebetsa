import { describe, it, expect } from 'vitest';
import { NAV_MODEL, resolveNavForRole } from '@/features/rbac/constants/navigation';
import type { UserRole } from '@/features/auth/types/auth.types';

function labels(role: UserRole | null): string[] {
  return resolveNavForRole(role).flatMap((g) => g.items.map((i) => i.label));
}

describe('resolveNavForRole', () => {
  it('never renders an empty group', () => {
    for (const role of [
      'organization_administrator',
      'operations_manager',
      'hr_user',
      'employee',
      'client_user',
      null,
    ] as const) {
      for (const group of resolveNavForRole(role)) {
        expect(group.items.length).toBeGreaterThan(0);
      }
    }
  });

  it('gives every non-client role Dashboard, Notifications and My Profile', () => {
    for (const role of [
      'organization_administrator',
      'operations_manager',
      'regional_manager',
      'site_manager',
      'supervisor',
      'hr_user',
      'employee',
    ] as const) {
      const l = labels(role);
      expect(l).toContain('Dashboard');
      expect(l).toContain('Notifications');
      expect(l).toContain('My Profile');
    }
  });

  it('scopes the employee role to their own operational work only', () => {
    const l = labels('employee');
    expect(l).toEqual(expect.arrayContaining(['Attendance']));
    for (const forbidden of ['Employees', 'Teams', 'Departments', 'Positions', 'Site Assignments', 'Users & Roles', 'Organizations']) {
      expect(l).not.toContain(forbidden);
    }
  });

  it('scopes HR to workforce structure (not day-to-day operational assignment)', () => {
    const l = labels('hr_user');
    expect(l).toEqual(expect.arrayContaining(['Employees', 'Departments', 'Positions', 'Users & Roles']));
    expect(l).not.toContain('Organizations');
  });

  it('gives operational-tier roles (regional/site manager, supervisor) the Teams and Site Assignments nav', () => {
    for (const role of ['regional_manager', 'site_manager', 'supervisor'] as const) {
      const l = labels(role);
      expect(l).toEqual(expect.arrayContaining(['Teams', 'Site Assignments']));
    }
  });

  it('gives the organization administrator workforce + attendance + admin navigation', () => {
    const l = labels('organization_administrator');
    expect(l).toEqual(
      expect.arrayContaining([
        'Employees',
        'Teams',
        'Departments',
        'Positions',
        'Site Assignments',
        'Attendance',
        'Users & Roles',
      ]),
    );
  });

  it('gives org_structure.view holders the Regions/Clients/Sites/Contracts group', () => {
    for (const role of ['organization_administrator', 'operations_manager', 'regional_manager', 'site_manager'] as const) {
      const l = labels(role);
      expect(l).toEqual(expect.arrayContaining(['Regions', 'Clients', 'Sites', 'Contracts']));
    }
  });

  it('hides the org hierarchy from roles without org_structure.view', () => {
    for (const role of ['employee', 'client_user'] as const) {
      const l = labels(role);
      for (const forbidden of ['Regions', 'Clients', 'Sites', 'Contracts']) {
        expect(l).not.toContain(forbidden);
      }
    }
  });

  it('restricts Users & Roles to profile.manage_any holders', () => {
    expect(labels('organization_administrator')).toContain('Users & Roles');
    expect(labels('hr_user')).toContain('Users & Roles');
    for (const role of ['employee', 'client_user', 'supervisor'] as const) {
      expect(labels(role)).not.toContain('Users & Roles');
    }
  });

  it('restricts Organizations (tenant switching) to platform admins', () => {
    expect(labels('platform_administrator')).toContain('Organizations');
    expect(labels('organization_administrator')).not.toContain('Organizations');
  });

  it('gives a client_user a minimal honest nav', () => {
    const l = labels('client_user');
    expect(l.sort()).toEqual(['Dashboard', 'Notifications', 'Notification Preferences', 'My Profile'].sort());
  });

  it('every item in the model has a real destination path', () => {
    for (const group of NAV_MODEL) {
      for (const item of group.items) {
        expect(item.path).toMatch(/^\//);
      }
    }
  });
});
