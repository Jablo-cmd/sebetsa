import { supabase } from '@/lib/supabase';
import type { EmployeeDocumentRow } from '@/lib/dbTypes';
import type { EmployeeDocument, DocumentType } from '@/features/documents/types/document.types';

function toDocument(row: EmployeeDocumentRow): EmployeeDocument {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    documentType: row.document_type,
    fileName: row.file_name,
    mimeType: row.mime_type,
    fileSizeBytes: row.file_size_bytes,
    storagePath: row.storage_path,
    version: row.version,
    supersedesDocumentId: row.supersedes_document_id,
    status: row.status,
    expiryDate: row.expiry_date,
    uploadedBy: row.uploaded_by,
    verifiedBy: row.verified_by,
    verifiedAt: row.verified_at,
    reviewNotes: row.review_notes,
    createdAt: row.created_at,
  };
}

const BUCKET = 'employee-documents';

async function getDocuments(employeeId: string): Promise<EmployeeDocument[]> {
  const { data, error } = await supabase.from('employee_documents').select('*').eq('employee_id', employeeId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toDocument);
}

/** Creates the metadata row (server-generated storage path), then uploads the actual file bytes to that exact path. */
async function uploadDocument(
  employeeId: string,
  documentType: DocumentType,
  file: File,
  expiryDate?: string,
): Promise<EmployeeDocument> {
  const { data: slot, error: slotError } = await supabase.rpc('create_document_upload_slot', {
    p_employee_id: employeeId,
    p_document_type: documentType,
    p_file_name: file.name,
    p_mime_type: file.type,
    p_file_size_bytes: file.size,
    p_expiry_date: expiryDate,
  });
  if (slotError) throw slotError;

  const { error: uploadError } = await supabase.storage.from(BUCKET).upload(slot.storage_path, file, { contentType: file.type });
  if (uploadError) throw uploadError;

  return toDocument(slot);
}

async function replaceDocument(oldDocumentId: string, file: File, expiryDate?: string): Promise<EmployeeDocument> {
  const { data: newRow, error: rpcError } = await supabase.rpc('replace_document', {
    p_old_document_id: oldDocumentId,
    p_file_name: file.name,
    p_mime_type: file.type,
    p_file_size_bytes: file.size,
    p_expiry_date: expiryDate,
  });
  if (rpcError) throw rpcError;

  const { error: uploadError } = await supabase.storage.from(BUCKET).upload(newRow.storage_path, file, { contentType: file.type });
  if (uploadError) throw uploadError;

  return toDocument(newRow);
}

async function getSignedUrl(storagePath: string): Promise<string> {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(storagePath, 300);
  if (error) throw error;
  return data.signedUrl;
}

async function verifyDocument(documentId: string, approve: boolean, reviewNotes?: string): Promise<EmployeeDocument> {
  const { data, error } = await supabase.rpc('verify_document', { p_document_id: documentId, p_approve: approve, p_review_notes: reviewNotes });
  if (error) throw error;
  return toDocument(data);
}

async function syncExpiredDocuments(tenantId: string): Promise<EmployeeDocument[]> {
  const { data, error } = await supabase.rpc('sync_expired_documents', { p_tenant_id: tenantId });
  if (error) throw error;
  return (data ?? []).map(toDocument);
}

export const documentService = {
  getDocuments,
  uploadDocument,
  replaceDocument,
  getSignedUrl,
  verifyDocument,
  syncExpiredDocuments,
};
