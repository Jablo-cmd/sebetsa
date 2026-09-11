import { supabase } from '@/lib/supabase';
import type { ContractRow, ContractInsert, ContractUpdate } from '@/lib/dbTypes';
import type {
  Contract,
  CreateContractInput,
  UpdateContractInput,
  ContractsListFilters,
  ContractsListPage,
} from '@/features/orgStructure/types/orgStructure.types';

const DEFAULT_PAGE_SIZE = 20;

export interface ManagerCandidate {
  id: string;
  firstName: string;
  lastName: string;
}

/** Search-driven candidate lookup for the "responsible manager" picker — profiles within the tenant. */
async function searchManagerCandidates(tenantId: string, search = ''): Promise<ManagerCandidate[]> {
  let query = supabase.from('profiles').select('id, first_name, last_name').eq('tenant_id', tenantId);

  const term = search.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.or(`first_name.ilike.%${escaped}%,last_name.ilike.%${escaped}%`);
  }

  const { data, error } = await query.order('first_name', { ascending: true }).limit(20);
  if (error) throw error;
  return data.map((row) => ({ id: row.id, firstName: row.first_name, lastName: row.last_name }));
}

export function toContract(row: ContractRow): Contract {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    contractNumber: row.contract_number,
    startDate: row.start_date,
    endDate: row.end_date,
    status: row.status,
    responsibleManagerId: row.responsible_manager_id,
    slaNotes: row.sla_notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getContracts(
  tenantId: string,
  filters: ContractsListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<ContractsListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('contracts').select('*', { count: 'exact' }).eq('tenant_id', tenantId);

  const term = filters.search?.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.ilike('contract_number', `%${escaped}%`);
  }
  if (filters.clientId) query = query.eq('client_id', filters.clientId);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error, count } = await query.order('start_date', { ascending: false }).range(from, to);
  if (error) throw error;

  return { contracts: data.map(toContract), totalCount: count ?? 0, page, pageSize };
}

/** Every contract for one client, unpaginated — fits a client detail-page section. */
async function getContractsForClient(clientId: string): Promise<Contract[]> {
  const { data, error } = await supabase
    .from('contracts')
    .select('*')
    .eq('client_id', clientId)
    .order('start_date', { ascending: false });
  if (error) throw error;
  return data.map(toContract);
}

/** Every contract covering one site, via the contract_sites junction — fits a site detail-page section. */
async function getContractsForSite(siteId: string): Promise<Contract[]> {
  const { data, error } = await supabase
    .from('contract_sites')
    .select('contract:contracts(*)')
    .eq('site_id', siteId);
  if (error) throw error;
  return data
    .map((row) => row.contract)
    .filter((contract): contract is NonNullable<typeof contract> => contract !== null)
    .map(toContract);
}

async function getContract(id: string): Promise<Contract | null> {
  const { data, error } = await supabase.from('contracts').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toContract(data) : null;
}

/** Site ids currently linked to a contract via contract_sites. */
async function getContractSiteIds(contractId: string): Promise<string[]> {
  const { data, error } = await supabase.from('contract_sites').select('site_id').eq('contract_id', contractId);
  if (error) throw error;
  return data.map((row) => row.site_id);
}

async function setContractSites(tenantId: string, contractId: string, siteIds: string[]): Promise<void> {
  const { error: deleteError } = await supabase.from('contract_sites').delete().eq('contract_id', contractId);
  if (deleteError) throw deleteError;

  if (siteIds.length === 0) return;

  const { error: insertError } = await supabase
    .from('contract_sites')
    .insert(siteIds.map((siteId) => ({ contract_id: contractId, site_id: siteId, tenant_id: tenantId })));
  if (insertError) throw insertError;
}

function toInsertPayload(tenantId: string, input: CreateContractInput): ContractInsert {
  return {
    tenant_id: tenantId,
    client_id: input.clientId,
    contract_number: input.contractNumber,
    start_date: input.startDate,
    end_date: input.endDate ?? null,
    status: input.status ?? undefined,
    responsible_manager_id: input.responsibleManagerId ?? null,
    sla_notes: input.slaNotes ?? null,
  };
}

async function createContract(tenantId: string, input: CreateContractInput): Promise<Contract> {
  const { data, error } = await supabase.from('contracts').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  const contract = toContract(data);
  if (input.siteIds && input.siteIds.length > 0) {
    await setContractSites(tenantId, contract.id, input.siteIds);
  }
  return contract;
}

async function updateContract(id: string, updates: UpdateContractInput): Promise<Contract> {
  const payload: ContractUpdate = {};
  if (updates.clientId !== undefined) payload.client_id = updates.clientId;
  if (updates.contractNumber !== undefined) payload.contract_number = updates.contractNumber;
  if (updates.startDate !== undefined) payload.start_date = updates.startDate;
  if (updates.endDate !== undefined) payload.end_date = updates.endDate;
  if (updates.status !== undefined) payload.status = updates.status;
  if (updates.responsibleManagerId !== undefined) payload.responsible_manager_id = updates.responsibleManagerId;
  if (updates.slaNotes !== undefined) payload.sla_notes = updates.slaNotes;

  const { data, error } = await supabase.from('contracts').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toContract(data);
}

async function updateContractStatus(id: string, status: Contract['status']): Promise<Contract> {
  return updateContract(id, { status });
}

export const contractService = {
  searchManagerCandidates,
  getContracts,
  getContractsForClient,
  getContractsForSite,
  getContract,
  getContractSiteIds,
  setContractSites,
  createContract,
  updateContract,
  updateContractStatus,
};
