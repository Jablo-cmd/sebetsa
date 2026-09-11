import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface SiteOption {
  id: string;
  name: string;
}

/** Minimal site picker source for the Attendance page — a full Sites directory (CRUD, client/region linkage) is a later phase. */
export function useSitesList(tenantId: string | undefined) {
  const [sites, setSites] = useState<SiteOption[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId) {
      setSites([]);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const { data, error: dbError } = await supabase
        .from('sites')
        .select('id, name')
        .eq('tenant_id', tenantId)
        .order('name', { ascending: true });
      if (dbError) throw dbError;
      setSites(data);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load sites.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { sites, isLoading, error };
}
