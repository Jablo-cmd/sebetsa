import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Pagination } from '@/components/ui/Pagination';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useSiteSurveysList } from '@/features/siteSurveys/hooks/useSiteSurveys';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { SiteSurveyFormModal } from '@/features/siteSurveys/components/SiteSurveyFormModal';
import type { SiteSurveyStatus } from '@/features/siteSurveys/types/siteSurvey.types';

const STATUS_TONE: Record<SiteSurveyStatus, StatusTone> = {
  draft: 'neutral',
  completed: 'info',
  converted: 'success',
};

/** LEAD -> SITE SURVEY: a field capture of a prospective site's building/access/requirements, convertible into a real site once the client is won. */
export function SiteSurveysPage() {
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { surveys, totalCount, page, pageSize, isLoading, error, setPage, refetch } = useSiteSurveysList(organization?.id);
  const { clients } = useAllClients(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  const clientName = (clientId: string) => clients.find((c) => c.id === clientId)?.name ?? '—';

  return (
    <PageContainer>
      <PageHeader
        title="Site Surveys"
        description="Field surveys of prospective sites — convert one into a real site once the client is won."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)} disabled={clients.length === 0}>
                Start survey
              </Button>
            </div>
          )
        }
      />

      {organization && clients.length === 0 && (
        <p className="rounded-card border border-dashed border-border-strong bg-surface-raised px-4 py-6 text-center text-sm text-content-tertiary">
          Add a client before starting a site survey.
        </p>
      )}

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="site surveys" />
      ) : isLoading ? (
        <LoadingBlock label="Loading site surveys…" />
      ) : surveys.length === 0 ? (
        <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
          No site surveys yet.
        </div>
      ) : (
        <>
          <TableScrollContainer>
            <table className="w-full min-w-[600px] text-left text-sm">
              <thead>
                <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
                  <th scope="col" className="px-4 py-3 font-medium">
                    Site
                  </th>
                  <th scope="col" className="px-4 py-3 font-medium">
                    Client
                  </th>
                  <th scope="col" className="px-4 py-3 font-medium">
                    Status
                  </th>
                </tr>
              </thead>
              <tbody>
                {surveys.map((survey) => (
                  <tr key={survey.id} className="border-b border-border last:border-0">
                    <td className="px-4 py-3 font-medium text-content-primary">
                      <Link to={`/site-surveys/${survey.id}`} className="focus-ring rounded hover:text-brand-600">
                        {survey.prospectiveSiteName}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-content-secondary">{clientName(survey.clientId)}</td>
                    <td className="px-4 py-3">
                      <StatusBadge label={survey.status} tone={STATUS_TONE[survey.status]} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableScrollContainer>
          <Pagination page={page} pageSize={pageSize} totalCount={totalCount} onPageChange={setPage} resource="site surveys" />
        </>
      )}

      {organization && (
        <SiteSurveyFormModal isOpen={isCreateOpen} onClose={() => setIsCreateOpen(false)} tenantId={organization.id} clients={clients} onSaved={() => void refetch()} />
      )}
    </PageContainer>
  );
}
