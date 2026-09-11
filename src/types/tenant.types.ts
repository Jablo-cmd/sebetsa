import type { Organization } from '@/types/organization.types';

export type TenantStatus = 'idle' | 'loading' | 'ready' | 'missing' | 'inactive' | 'error';

/**
 * The resolved tenant context for the current session: which organization is
 * active, and whether that's because the user natively belongs to it or
 * because a platform-level role (platform admin) is viewing it via
 * cross-tenant access.
 */
export interface Tenant {
  id: string;
  organization: Organization;
  isPlatformLevelAccess: boolean;
}
