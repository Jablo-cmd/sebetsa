import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { useRegions } from '@/features/orgStructure/hooks/useRegions';
import { useTeams } from '@/features/teams/hooks/useTeams';
import { userScopeService, type ScopeType, type UserScope } from '@/features/users/services/userScopeService';
import { getDbErrorMessage } from '@/lib/dbErrors';

const TYPE_LABELS: Record<ScopeType, string> = { region: 'Region', site: 'Site', team: 'Team' };

export interface UserScopesSectionProps {
  tenantId: string;
  profileId: string;
  /** Whether the viewer may grant/revoke (org_structure.manage). */
  canManage: boolean;
}

/**
 * Regional managers, site managers and supervisors only reach site-bound
 * operational records inside the regions, sites or teams assigned here — the
 * database fails closed, so a user with no scope sees nothing.
 */
export function UserScopesSection({ tenantId, profileId, canManage }: UserScopesSectionProps) {
  const { regions } = useRegions(tenantId);
  const { sites } = useAllSites(tenantId);
  const { teams } = useTeams(tenantId);
  const [scopes, setScopes] = useState<UserScope[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [scopeType, setScopeType] = useState<ScopeType>('site');
  const [scopeId, setScopeId] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      setScopes(await userScopeService.getScopes(profileId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load access scopes.'));
    } finally {
      setIsLoading(false);
    }
  }, [profileId]);

  useEffect(() => {
    void load();
  }, [load]);

  const options: { id: string; name: string }[] =
    scopeType === 'region' ? regions : scopeType === 'site' ? sites : teams;
  const nameOf = (scope: UserScope) =>
    [...regions, ...sites, ...teams].find((x) => x.id === scope.scopeId)?.name ?? 'Unknown (removed)';

  const handleGrant = async () => {
    if (!scopeId) return;
    setIsSaving(true);
    setError(null);
    try {
      await userScopeService.grantScope(profileId, scopeType, scopeId);
      setScopeId('');
      await load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to grant access.'));
    } finally {
      setIsSaving(false);
    }
  };

  const handleRevoke = async (scope: UserScope) => {
    setError(null);
    try {
      await userScopeService.revokeScope(scope.id);
      await load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to revoke access.'));
    }
  };

  return (
    <section className="flex flex-col gap-3" aria-labelledby="user-scopes-heading">
      <h2 id="user-scopes-heading" className="text-base font-semibold text-content-primary">
        Access scope
      </h2>
      <ErrorAlert message={error} />
      {isLoading ? (
        <p className="text-sm text-content-tertiary">Loading access scope…</p>
      ) : scopes.length === 0 ? (
        <p role="status" className="rounded-card border border-warning-500/40 bg-warning-50 px-4 py-4 text-sm text-warning-600 dark:bg-warning-500/10 dark:text-warning-500">
          No access scope is assigned. This user cannot see site-based operational records (shifts, attendance, tasks,
          incidents, compliance, assets, inventory, procurement) until a region, site or team is granted.
        </p>
      ) : (
        <ul className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
          {scopes.map((scope) => (
            <li key={scope.id} className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
              <span>
                <span className="mr-2 text-xs uppercase tracking-wide text-content-tertiary">{TYPE_LABELS[scope.scopeType]}</span>
                <span className="font-medium text-content-primary">{nameOf(scope)}</span>
              </span>
              {canManage && (
                <button
                  type="button"
                  aria-label={`Revoke ${TYPE_LABELS[scope.scopeType]} ${nameOf(scope)}`}
                  onClick={() => void handleRevoke(scope)}
                  className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50"
                >
                  Revoke
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {canManage && (
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-sm">
            Scope type
            <select
              value={scopeType}
              onChange={(event) => {
                setScopeType(event.target.value as ScopeType);
                setScopeId('');
              }}
              className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3"
            >
              <option value="region">Region</option>
              <option value="site">Site</option>
              <option value="team">Team</option>
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Grant access to
            <select
              value={scopeId}
              onChange={(event) => setScopeId(event.target.value)}
              className="focus-ring h-11 min-w-[12rem] rounded-lg border border-border-strong bg-surface-raised px-3"
            >
              <option value="">Select…</option>
              {options.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.name}
                </option>
              ))}
            </select>
          </label>
          <Button variant="secondary" onClick={() => void handleGrant()} isLoading={isSaving} disabled={!scopeId}>
            Grant access
          </Button>
        </div>
      )}
    </section>
  );
}
