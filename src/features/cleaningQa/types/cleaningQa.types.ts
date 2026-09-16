import type { Database } from '@/lib/database.types';

export type InspectionStatus = Database['public']['Enums']['inspection_status'];
export type DefectSeverity = Database['public']['Enums']['defect_severity'];
export type DefectStatus = Database['public']['Enums']['defect_status'];

export interface InspectionTemplate {
  id: string;
  tenantId: string;
  name: string;
  description: string | null;
  category: string | null;
  passThreshold: number;
  isActive: boolean;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface InspectionTemplateItem {
  id: string;
  tenantId: string;
  templateId: string;
  areaLabel: string;
  criterion: string;
  maxScore: number;
  weight: number;
  sortOrder: number;
  createdAt: string;
}

export interface Inspection {
  id: string;
  tenantId: string;
  clientId: string;
  siteId: string;
  contractId: string | null;
  variationOrderId: string | null;
  templateId: string;
  inspectorId: string | null;
  status: InspectionStatus;
  scheduledAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  closedAt: string | null;
  overallScore: number | null;
  passed: boolean | null;
  notes: string | null;
  reinspectionOf: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface InspectionResult {
  id: string;
  tenantId: string;
  inspectionId: string;
  templateItemId: string;
  score: number;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Defect {
  id: string;
  tenantId: string;
  inspectionId: string;
  inspectionResultId: string | null;
  severity: DefectSeverity;
  description: string;
  areaLabel: string | null;
  responsibleTeamId: string | null;
  dueDate: string | null;
  status: DefectStatus;
  correctiveAction: string | null;
  resolutionNotes: string | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
  verifiedBy: string | null;
  verifiedAt: string | null;
  reinspectionId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateInspectionInput {
  clientId: string;
  siteId: string;
  contractId?: string | null;
  templateId: string;
  scheduledAt?: string | null;
}
