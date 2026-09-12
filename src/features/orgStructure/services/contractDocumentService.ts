import { supabase } from '@/lib/supabase';
import type { ContractDocumentRow } from '@/lib/dbTypes';

export interface ContractDocument {
  id: string;
  contractId: string;
  fileName: string;
  mimeType: string;
  fileSizeBytes: number;
  storagePath: string;
  version: number;
  createdAt: string;
}

function toDocument(row: ContractDocumentRow): ContractDocument {
  return {
    id: row.id,
    contractId: row.contract_id,
    fileName: row.file_name,
    mimeType: row.mime_type,
    fileSizeBytes: row.file_size_bytes,
    storagePath: row.storage_path,
    version: row.version,
    createdAt: row.created_at,
  };
}

const BUCKET = 'contract-documents';

async function getDocuments(contractId: string): Promise<ContractDocument[]> {
  const { data, error } = await supabase.from('contract_documents').select('*').eq('contract_id', contractId).order('version', { ascending: false });
  if (error) throw error;
  return data.map(toDocument);
}

/** Creates the metadata row (server-generated storage path/version), then uploads the actual file bytes to that exact path. */
async function uploadDocument(contractId: string, file: File): Promise<ContractDocument> {
  const { data: slot, error: slotError } = await supabase.rpc('create_contract_document_slot', {
    p_contract_id: contractId,
    p_file_name: file.name,
    p_mime_type: file.type,
    p_file_size_bytes: file.size,
  });
  if (slotError) throw slotError;

  const { error: uploadError } = await supabase.storage.from(BUCKET).upload(slot.storage_path, file, { contentType: file.type });
  if (uploadError) throw uploadError;

  return toDocument(slot);
}

async function getSignedUrl(storagePath: string): Promise<string> {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(storagePath, 300);
  if (error) throw error;
  return data.signedUrl;
}

export const contractDocumentService = {
  getDocuments,
  uploadDocument,
  getSignedUrl,
};
