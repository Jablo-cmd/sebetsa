import { useTenant } from '@/features/tenant/context/tenantContext';
import type { Organization } from '@/types/organization.types';

/** Convenience selector over useTenant() for call sites that only need the active organization. */
export function useCurrentOrganization(): Organization | null {
  return useTenant().tenant?.organization ?? null;
}
