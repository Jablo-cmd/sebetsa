import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { TextField } from '@/components/ui/TextField';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useTeam, useTeamMembers } from '@/features/teams/hooks/useTeams';
import { useSite } from '@/features/orgStructure/hooks/useSites';
import { teamService } from '@/features/teams/services/teamService';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { TeamFormModal } from '@/features/teams/components/TeamFormModal';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function TeamDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('team.manage');
  const organization = useCurrentOrganization();
  const { team, isLoading, error, refetch } = useTeam(id);
  const { members, isLoading: membersLoading, refetch: refetchMembers } = useTeamMembers(id);
  const { site } = useSite(team?.siteId ?? undefined);
  const { sites } = useAllSites(organization?.id);

  const [isEditOpen, setIsEditOpen] = useState(false);
  const [memberSearch, setMemberSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    if (!organization || !memberSearch.trim()) {
      setCandidates([]);
      return;
    }
    let cancelled = false;
    void employeeService.searchEmployeeCandidates(organization.id, memberSearch).then((results) => {
      if (!cancelled) setCandidates(results.filter((c) => !members.some((m) => m.employeeId === c.id)));
    });
    return () => {
      cancelled = true;
    };
  }, [organization, memberSearch, members]);

  if (isLoading) {
    return <FullScreenSpinner label="Loading team…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!team) {
    return (
      <FullScreenNotice
        title="Team not found"
        message="This team doesn't exist, or you don't have access to view it."
        action={
          <Link to="/teams" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Teams
          </Link>
        }
      />
    );
  }

  const handleAddMember = async (employeeId: string) => {
    if (!organization) return;
    setActionError(null);
    try {
      await teamService.addTeamMember(organization.id, team.id, employeeId);
      setMemberSearch('');
      await refetchMembers();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to add team member.'));
    }
  };

  const handleRemoveMember = async (employeeId: string) => {
    setActionError(null);
    try {
      await teamService.removeTeamMember(team.id, employeeId);
      await refetchMembers();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to remove team member.'));
    }
  };

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/teams')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Teams
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{team.name}</h1>
            <p className="text-sm text-content-secondary">
              {site ? (
                <Link to={`/sites/${site.id}`} className="text-brand-600 hover:underline">
                  {site.name}
                </Link>
              ) : (
                'No site assigned'
              )}
            </p>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
            {team.status}
          </span>
        </div>

        {canManage && (
          <div className="mt-6 border-t border-border pt-5">
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" onClick={() => setIsEditOpen(true)}>
                Edit details
              </Button>
            </div>
          </div>
        )}
      </div>

      <ErrorAlert message={actionError} />

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Members</h2>

        {membersLoading ? (
          <p className="text-sm text-content-tertiary">Loading members…</p>
        ) : members.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No members in this team yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {members.map((member) => (
              <div key={member.employeeId} className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
                <Link to={`/employees/${member.employeeId}`} className="focus-ring rounded font-medium text-content-primary hover:text-brand-600">
                  {member.employeeFirstName} {member.employeeLastName}
                  <span className="ml-2 font-normal text-content-tertiary">{member.employeeNumber}</span>
                </Link>
                {canManage && (
                  <button
                    type="button"
                    onClick={() => void handleRemoveMember(member.employeeId)}
                    className="focus-ring rounded-md px-2 py-1 text-xs font-medium text-danger-600 hover:bg-danger-50"
                  >
                    Remove
                  </button>
                )}
              </div>
            ))}
          </div>
        )}

        {canManage && (
          <div>
            <TextField
              label="Add a member"
              placeholder="Search by name…"
              value={memberSearch}
              onChange={(event) => setMemberSearch(event.target.value)}
            />
            {candidates.length > 0 && (
              <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
                {candidates.map((candidate) => (
                  <button
                    key={candidate.id}
                    type="button"
                    onClick={() => void handleAddMember(candidate.id)}
                    className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3 py-2 text-left text-sm hover:bg-surface-sunken"
                  >
                    {candidate.firstName} {candidate.lastName}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </section>

      {organization && (
        <TeamFormModal
          isOpen={isEditOpen}
          onClose={() => setIsEditOpen(false)}
          tenantId={organization.id}
          team={team}
          sites={sites}
          onSaved={() => void refetch()}
        />
      )}
    </div>
  );
}
