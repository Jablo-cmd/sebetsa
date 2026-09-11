import { supabase } from '@/lib/supabase';
import type { ClientRow, ClientInsert, ClientUpdate } from '@/lib/dbTypes';
import type {
  Client,
  CreateClientInput,
  UpdateClientInput,
  ClientsListFilters,
  ClientsListPage,
} from '@/features/orgStructure/types/orgStructure.types';

const DEFAULT_PAGE_SIZE = 20;

export function toClient(row: ClientRow): Client {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    regionId: row.region_id,
    name: row.name,
    industry: row.industry,
    primaryContactName: row.primary_contact_name,
    primaryContactEmail: row.primary_contact_email,
    primaryContactPhone: row.primary_contact_phone,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getClients(
  tenantId: string,
  filters: ClientsListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<ClientsListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('clients').select('*', { count: 'exact' }).eq('tenant_id', tenantId);

  const term = filters.search?.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.or(`name.ilike.%${escaped}%,industry.ilike.%${escaped}%`);
  }
  if (filters.regionId) query = query.eq('region_id', filters.regionId);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error, count } = await query.order('name', { ascending: true }).range(from, to);
  if (error) throw error;

  return { clients: data.map(toClient), totalCount: count ?? 0, page, pageSize };
}

/** Every client for the tenant, unpaginated — for pickers (site/contract forms) where a bounded catalogue is expected. */
async function getAllClients(tenantId: string): Promise<Client[]> {
  const { data, error } = await supabase
    .from('clients')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toClient);
}

async function getClient(id: string): Promise<Client | null> {
  const { data, error } = await supabase.from('clients').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toClient(data) : null;
}

function toInsertPayload(tenantId: string, input: CreateClientInput): ClientInsert {
  return {
    tenant_id: tenantId,
    region_id: input.regionId ?? null,
    name: input.name,
    industry: input.industry ?? null,
    primary_contact_name: input.primaryContactName ?? null,
    primary_contact_email: input.primaryContactEmail ?? null,
    primary_contact_phone: input.primaryContactPhone ?? null,
    status: input.status ?? undefined,
  };
}

async function createClient(tenantId: string, input: CreateClientInput): Promise<Client> {
  const { data, error } = await supabase.from('clients').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toClient(data);
}

async function updateClient(id: string, updates: UpdateClientInput): Promise<Client> {
  const payload: ClientUpdate = {};
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.regionId !== undefined) payload.region_id = updates.regionId;
  if (updates.industry !== undefined) payload.industry = updates.industry;
  if (updates.primaryContactName !== undefined) payload.primary_contact_name = updates.primaryContactName;
  if (updates.primaryContactEmail !== undefined) payload.primary_contact_email = updates.primaryContactEmail;
  if (updates.primaryContactPhone !== undefined) payload.primary_contact_phone = updates.primaryContactPhone;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('clients').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toClient(data);
}

async function archiveClient(id: string): Promise<Client> {
  return updateClient(id, { status: 'inactive' });
}

async function restoreClient(id: string): Promise<Client> {
  return updateClient(id, { status: 'active' });
}

export const clientService = {
  getClients,
  getAllClients,
  getClient,
  createClient,
  updateClient,
  archiveClient,
  restoreClient,
};
