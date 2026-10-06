import { useRef, useState, type ChangeEvent } from 'react';
import { Button } from '@/components/ui/Button';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { documentService } from '@/features/documents/services/documentService';
import { ACCEPTED_MIME_TYPES, MAX_FILE_SIZE_BYTES, type EmployeeDocument } from '@/features/documents/types/document.types';
import type { DocumentStatusEnum } from '@/lib/dbTypes';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_LABEL: Record<string, string> = {
  uploaded: 'Uploaded',
  pending_review: 'Pending review',
  verified: 'Verified',
  rejected: 'Rejected',
  expired: 'Expired',
  archived: 'Archived',
};

const STATUS_TONES: Record<DocumentStatusEnum, StatusTone> = {
  uploaded: 'neutral',
  pending_review: 'warning',
  verified: 'success',
  rejected: 'danger',
  expired: 'danger',
  archived: 'neutral',
};

export interface DocumentsTableProps {
  documents: EmployeeDocument[];
  canVerify?: boolean;
  onChanged: () => void;
}

export function DocumentsTable({ documents, canVerify = false, onChanged }: DocumentsTableProps) {
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [replaceTarget, setReplaceTarget] = useState<string | null>(null);
  const replaceInputRef = useRef<HTMLInputElement>(null);

  const handleView = async (storagePath: string) => {
    setError(null);
    try {
      const url = await documentService.getSignedUrl(storagePath);
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to open the document.'));
    }
  };

  const handleDecide = async (documentId: string, approve: boolean) => {
    setBusyId(documentId);
    setError(null);
    try {
      await documentService.verifyDocument(documentId, approve);
      onChanged();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to update the document.'));
    } finally {
      setBusyId(null);
    }
  };

  const startReplace = (documentId: string) => {
    setReplaceTarget(documentId);
    replaceInputRef.current?.click();
  };

  const handleReplaceFile = async (event: ChangeEvent<HTMLInputElement>) => {
    const selected = event.target.files?.[0] ?? null;
    event.target.value = '';
    const targetId = replaceTarget;
    setReplaceTarget(null);
    if (!selected || !targetId) return;
    setError(null);
    if (!ACCEPTED_MIME_TYPES.includes(selected.type as (typeof ACCEPTED_MIME_TYPES)[number])) {
      setError('Only PDF, JPEG, or PNG files are accepted.');
      return;
    }
    if (selected.size > MAX_FILE_SIZE_BYTES) {
      setError('Maximum file size is 10MB.');
      return;
    }
    setBusyId(targetId);
    try {
      await documentService.replaceDocument(targetId, selected);
      onChanged();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to replace the document.'));
    } finally {
      setBusyId(null);
    }
  };

  if (documents.length === 0) {
    return <p className="py-4 text-sm text-content-secondary">No documents yet.</p>;
  }

  return (
    <div className="overflow-x-auto">
      <ErrorAlert message={error} />
      <input
        ref={replaceInputRef}
        type="file"
        className="sr-only"
        tabIndex={-1}
        aria-label="Replacement file"
        accept={ACCEPTED_MIME_TYPES.join(',')}
        onChange={(event) => void handleReplaceFile(event)}
      />
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase text-content-secondary">
            <th className="px-3 py-2">File</th>
            <th className="px-3 py-2">Type</th>
            <th className="px-3 py-2">Version</th>
            <th className="px-3 py-2">Status</th>
            <th className="px-3 py-2">Expiry</th>
            <th className="px-3 py-2 text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          {documents.map((doc) => (
            <tr key={doc.id} className="border-b border-border last:border-0">
              <td className="px-3 py-2.5">{doc.fileName}</td>
              <td className="px-3 py-2.5 capitalize">{doc.documentType.replace('_', ' ')}</td>
              <td className="px-3 py-2.5">v{doc.version}</td>
              <td className="px-3 py-2.5">
                <StatusBadge label={STATUS_LABEL[doc.status] ?? doc.status} tone={STATUS_TONES[doc.status]} />
              </td>
              <td className="px-3 py-2.5">{doc.expiryDate ?? '—'}</td>
              <td className="px-3 py-2.5 text-right">
                <div className="flex justify-end gap-1">
                  <Button variant="ghost" onClick={() => void handleView(doc.storagePath)}>
                    View
                  </Button>
                  {doc.status !== 'archived' && (
                    <Button variant="ghost" onClick={() => startReplace(doc.id)} isLoading={busyId === doc.id}>
                      Replace
                    </Button>
                  )}
                  {canVerify && ['uploaded', 'pending_review'].includes(doc.status) && (
                    <>
                      <Button variant="ghost" onClick={() => void handleDecide(doc.id, false)} isLoading={busyId === doc.id}>
                        Reject
                      </Button>
                      <Button variant="ghost" onClick={() => void handleDecide(doc.id, true)} isLoading={busyId === doc.id}>
                        Verify
                      </Button>
                    </>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
