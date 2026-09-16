import type { Database } from '@/lib/database.types';

export type EntityStatus = Database['public']['Enums']['entity_status'];
export type ContractStatus = Database['public']['Enums']['contract_status'];
export type ContractBillingFrequency = Database['public']['Enums']['contract_billing_frequency'];
export type ContractPartyResponsibility = Database['public']['Enums']['contract_party_responsibility'];
export type TaskPriority = Database['public']['Enums']['task_priority'];

export interface Region {
  id: string;
  tenantId: string;
  name: string;
  code: string | null;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateRegionInput {
  name: string;
  code?: string | null;
}

export interface UpdateRegionInput {
  name?: string;
  code?: string | null;
  status?: EntityStatus;
}

export interface Client {
  id: string;
  tenantId: string;
  regionId: string | null;
  name: string;
  industry: string | null;
  primaryContactName: string | null;
  primaryContactEmail: string | null;
  primaryContactPhone: string | null;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateClientInput {
  name: string;
  regionId?: string | null;
  industry?: string | null;
  primaryContactName?: string | null;
  primaryContactEmail?: string | null;
  primaryContactPhone?: string | null;
  status?: EntityStatus;
}

export type UpdateClientInput = Partial<CreateClientInput>;

export interface ClientsListFilters {
  search?: string;
  regionId?: string;
  status?: EntityStatus;
}

export interface ClientsListPage {
  clients: Client[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface Site {
  id: string;
  tenantId: string;
  clientId: string;
  regionId: string | null;
  name: string;
  address: string | null;
  siteType: string | null;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateSiteInput {
  clientId: string;
  regionId?: string | null;
  name: string;
  address?: string | null;
  siteType?: string | null;
  status?: EntityStatus;
}

export type UpdateSiteInput = Partial<CreateSiteInput>;

export interface SitesListFilters {
  search?: string;
  clientId?: string;
  regionId?: string;
  status?: EntityStatus;
}

export interface SitesListPage {
  sites: Site[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface Contract {
  id: string;
  tenantId: string;
  clientId: string;
  contractNumber: string;
  startDate: string;
  endDate: string | null;
  status: ContractStatus;
  responsibleManagerId: string | null;
  slaNotes: string | null;
  contractValue: number | null;
  recurringValue: number | null;
  billingFrequency: ContractBillingFrequency | null;
  paymentTermsDays: number | null;
  renewalDate: string | null;
  autoRenew: boolean;
  escalationPercentage: number | null;
  escalationNotes: string | null;
  serviceFrequency: string | null;
  consumablesResponsibility: ContractPartyResponsibility | null;
  equipmentResponsibility: ContractPartyResponsibility | null;
  labourNotes: string | null;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateContractInput {
  clientId: string;
  contractNumber: string;
  startDate: string;
  endDate?: string | null;
  status?: ContractStatus;
  responsibleManagerId?: string | null;
  slaNotes?: string | null;
  siteIds?: string[];
}

export type UpdateContractInput = Partial<Omit<CreateContractInput, 'siteIds'>>;

export interface UpdateContractCommercialTermsInput {
  contractValue?: number | null;
  recurringValue?: number | null;
  billingFrequency?: ContractBillingFrequency | null;
  paymentTermsDays?: number | null;
  renewalDate?: string | null;
  autoRenew?: boolean;
  escalationPercentage?: number | null;
  escalationNotes?: string | null;
  serviceFrequency?: string | null;
  consumablesResponsibility?: ContractPartyResponsibility | null;
  equipmentResponsibility?: ContractPartyResponsibility | null;
  labourNotes?: string | null;
  notes?: string | null;
}

export interface ContractsListFilters {
  search?: string;
  clientId?: string;
  status?: ContractStatus;
}

export interface ContractsListPage {
  contracts: Contract[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface ContractVersion {
  id: string;
  tenantId: string;
  contractId: string;
  versionNumber: number;
  snapshot: Record<string, unknown>;
  changeSummary: string;
  changedBy: string | null;
  effectiveDate: string;
  createdAt: string;
}

export interface SiteArea {
  id: string;
  tenantId: string;
  siteId: string;
  name: string;
  description: string | null;
  sortOrder: number;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateSiteAreaInput {
  siteId: string;
  name: string;
  description?: string | null;
  sortOrder?: number;
}

export type UpdateSiteAreaInput = Partial<Omit<CreateSiteAreaInput, 'siteId'>> & { status?: EntityStatus };

export interface ScopeOfWorkItem {
  id: string;
  tenantId: string;
  contractId: string;
  siteAreaId: string;
  taskName: string;
  frequency: string | null;
  estimatedMinutes: number | null;
  assignedRole: string | null;
  requiredEquipment: string | null;
  requiredConsumables: string | null;
  ppeNotes: string | null;
  instructions: string | null;
  requiresEvidence: boolean;
  priority: TaskPriority;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateScopeOfWorkItemInput {
  contractId: string;
  siteAreaId: string;
  taskName: string;
  frequency?: string | null;
  estimatedMinutes?: number | null;
  assignedRole?: string | null;
  requiredEquipment?: string | null;
  requiredConsumables?: string | null;
  ppeNotes?: string | null;
  instructions?: string | null;
  requiresEvidence?: boolean;
  priority?: TaskPriority;
}

export type UpdateScopeOfWorkItemInput = Partial<Omit<CreateScopeOfWorkItemInput, 'contractId' | 'siteAreaId'>> & { status?: EntityStatus };
