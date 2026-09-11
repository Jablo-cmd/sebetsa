import type { Database } from '@/lib/database.types';

export type EntityStatus = Database['public']['Enums']['entity_status'];
export type ContractStatus = Database['public']['Enums']['contract_status'];

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
