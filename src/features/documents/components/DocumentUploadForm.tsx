import { useState, type ChangeEvent } from 'react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { documentService } from '@/features/documents/services/documentService';
import { retryOnNetworkError } from '@/lib/retry';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { ACCEPTED_MIME_TYPES, MAX_FILE_SIZE_BYTES } from '@/features/documents/types/document.types';
import type { DocumentType } from '@/features/documents/types/document.types';

const DOCUMENT_TYPE_OPTIONS: { value: DocumentType; label: string }[] = [
  { value: 'id_document', label: 'ID document' },
  { value: 'qualification', label: 'Qualification' },
  { value: 'contract', label: 'Contract' },
  { value: 'certificate', label: 'Certificate' },
  { value: 'training_record', label: 'Training record' },
  { value: 'medical', label: 'Medical' },
  { value: 'disciplinary', label: 'Disciplinary' },
  { value: 'other', label: 'Other' },
];

export interface DocumentUploadFormProps {
  employeeId: string;
  onUploaded: () => void;
}

export function DocumentUploadForm({ employeeId, onUploaded }: DocumentUploadFormProps) {
  const [documentType, setDocumentType] = useState<DocumentType>('other');
  const [file, setFile] = useState<File | null>(null);
  const [expiryDate, setExpiryDate] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleFileChange = (event: ChangeEvent<HTMLInputElement>) => {
    const selected = event.target.files?.[0] ?? null;
    setError(null);
    if (selected && !ACCEPTED_MIME_TYPES.includes(selected.type as (typeof ACCEPTED_MIME_TYPES)[number])) {
      setError('Only PDF, JPEG, or PNG files are accepted.');
      setFile(null);
      return;
    }
    if (selected && selected.size > MAX_FILE_SIZE_BYTES) {
      setError('Maximum file size is 10MB.');
      setFile(null);
      return;
    }
    setFile(selected);
  };

  const handleUpload = async () => {
    if (!file) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await retryOnNetworkError(() => documentService.uploadDocument(employeeId, documentType, file, expiryDate || undefined));
      setFile(null);
      setExpiryDate('');
      onUploaded();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to upload the document.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex flex-col gap-3">
      {error && <p className="text-sm font-medium text-danger-600">{error}</p>}
      <div>
        <label htmlFor="document-type" className="mb-1.5 block text-sm font-medium text-content-primary">
          Document type
        </label>
        <select
          id="document-type"
          className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
          value={documentType}
          onChange={(event) => setDocumentType(event.target.value as DocumentType)}
        >
          {DOCUMENT_TYPE_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="document-file" className="mb-1.5 block text-sm font-medium text-content-primary">
          File (PDF, JPEG, or PNG — max 10MB)
        </label>
        <input
          id="document-file"
          type="file"
          accept={ACCEPTED_MIME_TYPES.join(',')}
          onChange={handleFileChange}
          className="focus-ring block w-full text-sm text-content-secondary file:mr-3 file:rounded-md file:border-0 file:bg-brand-50 file:px-3 file:py-2 file:text-sm file:font-medium file:text-brand-700"
        />
      </div>

      <TextField label="Expiry date (optional)" type="date" value={expiryDate} onChange={(event) => setExpiryDate(event.target.value)} />

      <Button onClick={() => void handleUpload()} isLoading={isSubmitting} disabled={!file}>
        Upload
      </Button>
    </div>
  );
}
