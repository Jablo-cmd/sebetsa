/**
 * Single import surface for cross-feature domain types. Each type is owned
 * by exactly one feature (auth owns Role, rbac owns Permission, etc.) —
 * this barrel re-exports rather than redefines, so there is one source of
 * truth per concept.
 */
export type { UserRole as Role } from '@/features/auth/types/auth.types';
export type { Permission } from '@/features/rbac/types/permission.types';
export type { Organization, OrganizationStatus } from '@/types/organization.types';
export type { Profile, ProfileStatus, UserProfile } from '@/types/profile.types';
export type { Tenant, TenantStatus } from '@/types/tenant.types';
export type { Session } from '@/types/session.types';
