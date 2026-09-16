import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Pagination } from '@/components/ui/Pagination';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useQuotesList } from '@/features/quotes/hooks/useQuotes';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { QuotesTable } from '@/features/quotes/components/QuotesTable';
import { QuoteFormModal } from '@/features/quotes/components/QuoteFormModal';

/** Sales/proposal pipeline — the revenue half of the CLIENT -> QUOTE -> CONTRACT chain. Internal-facing only in this pass; no client-facing quote portal exists yet (deferred alongside the rest of the client portal). */
export function QuotesPage() {
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { quotes, totalCount, page, pageSize, isLoading, error, filters, setFilters, setPage, refetch } = useQuotesList(organization?.id);
  const { clients } = useAllClients(organization?.id);
  const { sites } = useAllSites(organization?.id);

  const [isCreateOpen, setIsCreateOpen] = useState(false);

  return (
    <PageContainer>
      <PageHeader
        title="Quotes"
        description="Sales quotes and proposals — approve one to convert it into a contract."
        action={
          canManage &&
          organization && (
            <div className="w-full sm:w-auto sm:min-w-[9rem]">
              <Button type="button" onClick={() => setIsCreateOpen(true)} disabled={clients.length === 0}>
                Add quote
              </Button>
            </div>
          )
        }
      />

      {organization && clients.length === 0 && (
        <p className="rounded-card border border-dashed border-border-strong bg-surface-raised px-4 py-6 text-center text-sm text-content-tertiary">
          Add a client before creating quotes — every quote belongs to one.
        </p>
      )}

      {organization && (
        <div className="flex flex-wrap gap-2">
          <select
            aria-label="Filter by client"
            value={filters.clientId ?? ''}
            onChange={(event) => setFilters({ ...filters, clientId: event.target.value || undefined })}
            className="focus-ring h-10 rounded-lg border border-border-strong bg-surface-raised px-3 text-sm text-content-primary"
          >
            <option value="">All clients</option>
            {clients.map((client) => (
              <option key={client.id} value={client.id}>
                {client.name}
              </option>
            ))}
          </select>
        </div>
      )}

      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="quotes" />
      ) : isLoading ? (
        <LoadingBlock label="Loading quotes…" />
      ) : (
        <>
          <QuotesTable quotes={quotes} clients={clients} />
          <Pagination page={page} pageSize={pageSize} totalCount={totalCount} onPageChange={setPage} resource="quotes" />
        </>
      )}

      {organization && (
        <QuoteFormModal
          isOpen={isCreateOpen}
          onClose={() => setIsCreateOpen(false)}
          tenantId={organization.id}
          clients={clients}
          sites={sites}
          onSaved={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
