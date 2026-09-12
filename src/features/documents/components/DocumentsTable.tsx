import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { documentService } from '@/features/documents/services/documentService';
import type { EmployeeDocument } from '@/features/documents/types/document.types';

const STATUS_LABEL: Record<string, string> = {
  uploaded: 'Uploaded',
  pending_review: 'Pending review',
  verified: 'Verified',
  rejected: 'Rejected',
  expired: 'Expired',
  archived: 'Archived',
};

const STATUS_CLASSES: Record<string, string> = {
  uploaded: 'bg-surface-sunken text-content-secondary',
  pending_review: 'bg-warning-50 text-warning-700 dark:bg-warning-500/15 dark:text-warning-200',
  verified: 'bg-success-50 text-success-700 dark:bg-success-500/15 dark:text-success-200',
  rejected: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
  expired: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
  archived: 'bg-surface-sunken text-content-tertiary',
};

export interface DocumentsTableProps {
  documents: EmployeeDocument[];
  canVerify?: boolean;
  onChanged: () => void;
}

export function DocumentsTable({ documents, canVerify = false, onChanged }: DocumentsTableProps) {
  const [busyId, setBusyId] = useState<string | null>(null);

  const handleView = async (storagePath: string) => {
    const url = await documentService.getSignedUrl(storagePath);
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const handleDecide = async (documentId: string, approve: boolean) => {
    setBusyId(documentId);
    try {
      await documentService.verifyDocument(documentId, approve);
      onChanged();
    } finally {
      setBusyId(null);
    }
  };

  if (documents.length === 0) {
    return <p className="py-4 text-sm text-content-secondary">No documents yet.</p>;
  }

  return (
    <div className="overflow-x-auto">
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
                <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_CLASSES[doc.status] ?? ''}`}>
                  {STATUS_LABEL[doc.status] ?? doc.status}
                </span>
              </td>
              <td className="px-3 py-2.5">{doc.expiryDate ?? '—'}</td>
              <td className="px-3 py-2.5 text-right">
                <div className="flex justify-end gap-1">
                  <Button variant="ghost" onClick={() => void handleView(doc.storagePath)}>
                    View
                  </Button>
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
