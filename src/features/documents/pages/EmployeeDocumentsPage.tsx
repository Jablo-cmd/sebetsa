import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { TextField } from '@/components/ui/TextField';
import { Button } from '@/components/ui/Button';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { useEmployeeDocuments } from '@/features/documents/hooks/useEmployeeDocuments';
import { DocumentUploadForm } from '@/features/documents/components/DocumentUploadForm';
import { DocumentsTable } from '@/features/documents/components/DocumentsTable';
import { documentService } from '@/features/documents/services/documentService';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** HR/organization_administrator/operations_manager tier (can_manage_employees)
 * — visibility of medical/disciplinary categories is further narrowed at the
 * database layer to organization_administrator/hr_user only; this page
 * simply renders whatever the RLS-scoped query returns. */
export function EmployeeDocumentsPage() {
  const organization = useCurrentOrganization();
  const [employeeSearch, setEmployeeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedEmployee, setSelectedEmployee] = useState<EmployeeCandidate | null>(null);
  const { documents, isLoading, error, refetch } = useEmployeeDocuments(selectedEmployee?.id);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [isSyncing, setIsSyncing] = useState(false);

  if (!organization) return <NoActiveOrganizationNotice resource="employee documents" />;

  const searchEmployees = async (query: string) => {
    setEmployeeSearch(query);
    setCandidates(await employeeService.searchEmployeeCandidates(organization.id, query));
  };

  const handleSyncExpired = async () => {
    setIsSyncing(true);
    setSyncError(null);
    try {
      await documentService.syncExpiredDocuments(organization.id);
      void refetch();
    } catch (err) {
      setSyncError(getDbErrorMessage(err, 'Failed to sync expired documents.'));
    } finally {
      setIsSyncing(false);
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Employee Documents"
        description="Upload, verify, and manage employee documents."
        action={
          <Button variant="secondary" onClick={() => void handleSyncExpired()} isLoading={isSyncing}>
            Sync expired documents
          </Button>
        }
      />

      <ErrorAlert message={error ?? syncError} />

      <div className="mt-4">
        <TextField
          label="Employee"
          placeholder="Search by name…"
          hint={selectedEmployee ? `Selected: ${selectedEmployee.firstName} ${selectedEmployee.lastName}` : undefined}
          value={employeeSearch}
          onChange={(event) => void searchEmployees(event.target.value)}
        />
        <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
          {candidates.map((candidate) => (
            <button
              key={candidate.id}
              type="button"
              onClick={() => setSelectedEmployee(candidate)}
              className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                selectedEmployee?.id === candidate.id
                  ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                  : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
              }`}
            >
              {candidate.firstName} {candidate.lastName}
            </button>
          ))}
        </div>
      </div>

      {selectedEmployee && (
        <>
          <div className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
            <h2 className="text-sm font-semibold text-content-primary">Upload on behalf of {selectedEmployee.firstName}</h2>
            <div className="mt-3">
              <DocumentUploadForm employeeId={selectedEmployee.id} onUploaded={() => void refetch()} />
            </div>
          </div>

          <div className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
            {isLoading ? <p className="text-sm text-content-secondary">Loading…</p> : <DocumentsTable documents={documents} canVerify onChanged={() => void refetch()} />}
          </div>
        </>
      )}
    </PageContainer>
  );
}
