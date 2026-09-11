import { createContext, useContext } from 'react';
import type { Organization } from '@/types/organization.types';
import type { Tenant } from '@/types/tenant.types';
import type { CreateOrganizationInput } from '@/features/tenant/services/tenantService';

export type TenantLoadStatus = 'idle' | 'loading' | 'ready' | 'missing' | 'inactive' | 'error';

export interface TenantContextValue {
  status: TenantLoadStatus;
  tenant: Tenant | null;
  error: string | null;
  /** Populated only for platform-level roles (RBAC `tenant.switch` permission). */
  availableOrganizations: Organization[];
  /** True while the initial (or a refreshed) availableOrganizations fetch is in flight. */
  availableOrganizationsLoading: boolean;
  switchTenant: (organizationId: string) => Promise<void>;
  /** Creates a new organization (and adds it to availableOrganizations) — does NOT switch the active tenant to it; call switchTenant(organization.id) afterward if that's wanted. Platform-level roles only. */
  createOrganization: (input: CreateOrganizationInput) => Promise<Organization>;
  refetch: () => Promise<void>;
}

export const TenantContext = createContext<TenantContextValue | undefined>(undefined);

export function useTenant(): TenantContextValue {
  const context = useContext(TenantContext);
  if (!context) {
    throw new Error('useTenant must be used within a TenantProvider');
  }
  return context;
}
