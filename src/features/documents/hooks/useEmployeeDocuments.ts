import { useCallback, useEffect, useState } from 'react';
import { documentService } from '@/features/documents/services/documentService';
import type { EmployeeDocument } from '@/features/documents/types/document.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseEmployeeDocumentsResult {
  documents: EmployeeDocument[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useEmployeeDocuments(employeeId: string | undefined): UseEmployeeDocumentsResult {
  const [documents, setDocuments] = useState<EmployeeDocument[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!employeeId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setDocuments(await documentService.getDocuments(employeeId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load documents.'));
    } finally {
      setIsLoading(false);
    }
  }, [employeeId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { documents, isLoading, error, refetch: load };
}
