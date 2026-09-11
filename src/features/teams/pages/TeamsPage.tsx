import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useTeams } from '@/features/teams/hooks/useTeams';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { TeamsTable } from '@/features/teams/components/TeamsTable';
import { TeamFormModal } from '@/features/teams/components/TeamFormModal';

export function TeamsPage() {
  const { can } = usePermissions();
  const canManage = can('team.manage');
  const organization = useCurrentOrganization();
  const { teams, isLoading, error, refetch } = useTeams(organization?.id);
  const { sites } = useAllSites(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  return (
    <PageContainer>
      <PageHeader
        title="Teams"
        description="Operational workforce groupings, usually built around a site."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)}>
                Add team
              </Button>
            </div>
          )
        }
      />

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="teams" />
      ) : isLoading ? (
        <LoadingBlock label="Loading teams…" />
      ) : (
        <TeamsTable teams={teams} sites={sites} />
      )}

      {organization && (
        <TeamFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          sites={sites}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
