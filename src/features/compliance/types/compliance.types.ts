import type {
  ComplianceStatusEnum,
  IncidentActionStatusEnum,
  IncidentCategoryEnum,
  IncidentSeverityEnum,
  IncidentStatusEnum,
} from '@/lib/dbTypes';

export interface ComplianceRequirement {
  id: string;
  tenantId: string;
  name: string;
  category: string;
  description: string | null;
  appliesToScope: 'organization' | 'client' | 'site' | 'contract';
  recurrenceIntervalDays: number | null;
  isActive: boolean;
}

export interface ComplianceRecord {
  id: string;
  tenantId: string;
  requirementId: string;
  siteId: string | null;
  clientId: string | null;
  contractId: string | null;
  responsibleProfileId: string | null;
  status: ComplianceStatusEnum;
  dueDate: string | null;
  completedDate: string | null;
  expiryDate: string | null;
  evidenceStoragePath: string | null;
  verifiedBy: string | null;
  verifiedAt: string | null;
  notes: string | null;
}

export interface Incident {
  id: string;
  tenantId: string;
  referenceNumber: string;
  siteId: string | null;
  contractId: string | null;
  category: IncidentCategoryEnum;
  severity: IncidentSeverityEnum;
  status: IncidentStatusEnum;
  occurredAt: string;
  reportedBy: string | null;
  description: string;
  investigationNotes: string | null;
  correctiveActionSummary: string | null;
  closedBy: string | null;
  closedAt: string | null;
  createdAt: string;
}

export interface IncidentAction {
  id: string;
  tenantId: string;
  incidentId: string;
  description: string;
  ownerProfileId: string | null;
  dueDate: string | null;
  status: IncidentActionStatusEnum;
  completedAt: string | null;
  verifiedBy: string | null;
  verifiedAt: string | null;
}

export const INCIDENT_CATEGORY_LABELS: Record<IncidentCategoryEnum, string> = {
  workplace_safety: 'Workplace safety',
  property_damage: 'Property damage',
  client_incident: 'Client incident',
  near_miss: 'Near miss',
  security: 'Security',
  operational_other: 'Other operational',
};

export const INCIDENT_SEVERITY_LABELS: Record<IncidentSeverityEnum, string> = {
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  critical: 'Critical',
};

export const INCIDENT_STATUS_LABELS: Record<IncidentStatusEnum, string> = {
  reported: 'Reported',
  acknowledged: 'Acknowledged',
  investigating: 'Investigating',
  corrective_action: 'Corrective action',
  pending_closure: 'Pending closure',
  closed: 'Closed',
};
