import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useEmployeeDocuments } from '@/features/documents/hooks/useEmployeeDocuments';
import { DocumentUploadForm } from '@/features/documents/components/DocumentUploadForm';
import { DocumentsTable } from '@/features/documents/components/DocumentsTable';

/** Employee self-service: own documents only (RLS + create_document_upload_slot's own-employee check are the real boundary). */
export function MyDocumentsPage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();
  const { documents, isLoading, error, refetch } = useEmployeeDocuments(employee?.id);

  return (
    <PageContainer>
      <PageHeader title="My Documents" description="Your employment documents — IDs, qualifications, certificates, and more." />

      <OfflineBanner />
      <ErrorAlert message={employeeError ?? error} />

      {employeeLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : !employee ? (
        <p className="mt-6 text-sm text-content-secondary">No employee record is linked to your account.</p>
      ) : (
        <>
          <div className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
            <h2 className="text-sm font-semibold text-content-primary">Upload a document</h2>
            <div className="mt-3">
              <DocumentUploadForm employeeId={employee.id} onUploaded={() => void refetch()} />
            </div>
          </div>

          <div className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
            {isLoading ? <p className="text-sm text-content-secondary">Loading…</p> : <DocumentsTable documents={documents} onChanged={() => void refetch()} />}
          </div>
        </>
      )}
    </PageContainer>
  );
}
