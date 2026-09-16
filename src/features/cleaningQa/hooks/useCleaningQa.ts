import { useCallback, useEffect, useState } from 'react';
import { cleaningQaService } from '@/features/cleaningQa/services/cleaningQaService';
import type { Inspection, InspectionTemplate, InspectionTemplateItem, InspectionResult, Defect } from '@/features/cleaningQa/types/cleaningQa.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export function useInspectionTemplates(tenantId: string | undefined) {
  const [templates, setTemplates] = useState<InspectionTemplate[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setTemplates(await cleaningQaService.getTemplates(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load inspection templates.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { templates, isLoading, error, refetch };
}

export function useInspectionTemplateItems(templateId: string | undefined) {
  const [items, setItems] = useState<InspectionTemplateItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!templateId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      setItems(await cleaningQaService.getTemplateItems(templateId));
    } finally {
      setIsLoading(false);
    }
  }, [templateId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { items, isLoading, refetch };
}

export function useInspectionsList(tenantId: string | undefined) {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setInspections(await cleaningQaService.getInspections(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load inspections.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { inspections, isLoading, error, refetch };
}

export function useInspectionsForClient(clientId: string | undefined) {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!clientId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      setInspections(await cleaningQaService.getInspectionsForClient(clientId));
    } finally {
      setIsLoading(false);
    }
  }, [clientId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { inspections, isLoading, refetch };
}

export function useInspection(id: string | undefined) {
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!id) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setInspection(await cleaningQaService.getInspection(id));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load the inspection.'));
    } finally {
      setIsLoading(false);
    }
  }, [id]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { inspection, isLoading, error, refetch };
}

export function useInspectionResults(inspectionId: string | undefined) {
  const [results, setResults] = useState<InspectionResult[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!inspectionId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      setResults(await cleaningQaService.getResults(inspectionId));
    } finally {
      setIsLoading(false);
    }
  }, [inspectionId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { results, isLoading, refetch };
}

export function useDefects(inspectionId: string | undefined) {
  const [defects, setDefects] = useState<Defect[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!inspectionId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      setDefects(await cleaningQaService.getDefects(inspectionId));
    } finally {
      setIsLoading(false);
    }
  }, [inspectionId]);

  useEffect(() => {
    void refetch();
  }, [refetch]);

  return { defects, isLoading, refetch };
}
