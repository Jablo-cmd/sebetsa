export type DocumentType = 'id_document' | 'qualification' | 'contract' | 'certificate' | 'training_record' | 'medical' | 'disciplinary' | 'other';
export type DocumentStatus = 'uploaded' | 'pending_review' | 'verified' | 'rejected' | 'expired' | 'archived';

export const ACCEPTED_MIME_TYPES = ['application/pdf', 'image/jpeg', 'image/png'] as const;
export const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024;

export interface EmployeeDocument {
  id: string;
  tenantId: string;
  employeeId: string;
  documentType: DocumentType;
  fileName: string;
  mimeType: string;
  fileSizeBytes: number;
  storagePath: string;
  version: number;
  supersedesDocumentId: string | null;
  status: DocumentStatus;
  expiryDate: string | null;
  uploadedBy: string | null;
  verifiedBy: string | null;
  verifiedAt: string | null;
  reviewNotes: string | null;
  createdAt: string;
}
