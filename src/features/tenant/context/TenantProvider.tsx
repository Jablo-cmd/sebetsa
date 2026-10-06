import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { useAuth } from '@/features/auth/context/authContext';
import { useProfile } from '@/features/profile/context/profileContext';
import { tenantService } from '@/features/tenant/services/tenantService';
import type { CreateOrganizationInput } from '@/features/tenant/services/tenantService';
import { rbacService } from '@/features/rbac/services/rbacService';
import { TenantContext } from '@/features/tenant/context/tenantContext';
import type { TenantContextValue, TenantLoadStatus } from '@/features/tenant/context/tenantContext';
import type { Organization } from '@/types/organization.types';
import type { Tenant } from '@/types/tenant.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

/**
 * A platform-level user's chosen organisation lives only in memory, so a page
 * refresh used to drop it and every tenant page fell back to "No organization
 * selected". The choice is remembered per user for the browser session
 * (sessionStorage — cleared when the tab closes, never shared across users).
 */
const REMEMBERED_TENANT_PREFIX = 'sebetsa-active-organization:';

function readRememberedTenant(userId: string | undefined): string | null {
  if (!userId) return null;
  try {
    return window.sessionStorage.getItem(`${REMEMBERED_TENANT_PREFIX}${userId}`);
  } catch {
    return null;
  }
}

function writeRememberedTenant(userId: string | undefined, organizationId: string | null): void {
  if (!userId) return;
  try {
    const key = `${REMEMBERED_TENANT_PREFIX}${userId}`;
    if (organizationId) window.sessionStorage.setItem(key, organizationId);
    else window.sessionStorage.removeItem(key);
  } catch {
    /* storage unavailable: the selection simply is not remembered */
  }
}

export function TenantProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const { status: profileStatus, profile } = useProfile();

  const [status, setStatus] = useState<TenantLoadStatus>('idle');
  const [tenant, setTenant] = useState<Tenant | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [availableOrganizations, setAvailableOrganizations] = useState<Organization[]>([]);
  const [availableOrganizationsLoading, setAvailableOrganizationsLoading] = useState(false);

  const isPlatformLevel = rbacService.can(user?.role ?? null, 'tenant.switch');

  const loadTenant = useCallback(
    async (tenantId: string | null, isPlatformLevelAccess = false) => {
      if (!tenantId) {
        // No tenant on the profile: platform-level roles legitimately have
        // none (they operate across tenants); anyone else needs one assigned.
        setTenant(null);
        setStatus(isPlatformLevel ? 'ready' : 'missing');
        setError(null);
        return;
      }

      setStatus('loading');
      setError(null);
      try {
        const organization = await tenantService.getOrganizationById(tenantId);
        if (!organization) {
          setTenant(null);
          setStatus('missing');
          return;
        }
        setTenant({ id: organization.id, organization, isPlatformLevelAccess });
        setStatus(organization.status === 'active' ? 'ready' : 'inactive');
      } catch (err) {
        setTenant(null);
        setStatus('error');
        setError(getDbErrorMessage(err, 'Failed to load tenant.'));
      }
    },
    [isPlatformLevel],
  );

  useEffect(() => {
    if (isPlatformLevel && tenant) return;

    if (profileStatus === 'loaded' && profile) {
      const remembered = isPlatformLevel && !profile.tenantId ? readRememberedTenant(user?.id) : null;
      if (!remembered) {
        void loadTenant(profile.tenantId);
        return;
      }
      let isCurrent = true;
      setStatus('loading');
      tenantService
        .getOrganizationById(remembered)
        .then((organization) => {
          if (!isCurrent) return;
          if (!organization) throw new Error('remembered organization no longer exists');
          setTenant({ id: organization.id, organization, isPlatformLevelAccess: true });
          setStatus(organization.status === 'active' ? 'ready' : 'inactive');
        })
        .catch(() => {
          if (!isCurrent) return;
          writeRememberedTenant(user?.id, null);
          void loadTenant(null);
        });
      return () => {
        isCurrent = false;
      };
    } else if (profileStatus === 'missing' || profileStatus === 'error') {
      setTenant(null);
      setStatus('missing');
    } else if (profileStatus === 'idle') {
      setTenant(null);
      setStatus('idle');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profileStatus, profile?.tenantId, loadTenant, isPlatformLevel]);

  useEffect(() => {
    if (!isPlatformLevel) {
      setAvailableOrganizations([]);
      setAvailableOrganizationsLoading(false);
      return;
    }
    let isMounted = true;
    setAvailableOrganizationsLoading(true);
    tenantService
      .listAvailableOrganizations()
      .then((organizations) => {
        if (isMounted) setAvailableOrganizations(organizations);
      })
      .catch(() => {
        if (isMounted) setAvailableOrganizations([]);
      })
      .finally(() => {
        if (isMounted) setAvailableOrganizationsLoading(false);
      });
    return () => {
      isMounted = false;
    };
  }, [isPlatformLevel]);

  const switchTenant = useCallback(
    async (organizationId: string) => {
      if (!isPlatformLevel) {
        console.warn('Tenant switching is restricted to platform-level roles.');
        return;
      }
      await loadTenant(organizationId, true);
      writeRememberedTenant(user?.id, organizationId);
    },
    [isPlatformLevel, loadTenant, user?.id],
  );

  const createOrganization = useCallback(
    async (input: CreateOrganizationInput) => {
      if (!isPlatformLevel) {
        throw new Error('Organization creation is restricted to platform-level roles.');
      }
      const organization = await tenantService.createOrganization(input);
      setAvailableOrganizations((prev) => [...prev, organization].sort((a, b) => a.name.localeCompare(b.name)));
      return organization;
    },
    [isPlatformLevel],
  );

  const refetch = useCallback(async () => {
    if (tenant) {
      await loadTenant(tenant.id, tenant.isPlatformLevelAccess);
    } else if (profile) {
      await loadTenant(profile.tenantId);
    }
  }, [tenant, profile, loadTenant]);

  const value = useMemo<TenantContextValue>(
    () => ({
      status,
      tenant,
      error,
      availableOrganizations,
      availableOrganizationsLoading,
      switchTenant,
      createOrganization,
      refetch,
    }),
    [
      status,
      tenant,
      error,
      availableOrganizations,
      availableOrganizationsLoading,
      switchTenant,
      createOrganization,
      refetch,
    ],
  );

  return <TenantContext.Provider value={value}>{children}</TenantContext.Provider>;
}
