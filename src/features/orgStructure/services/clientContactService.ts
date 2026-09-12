import { supabase } from '@/lib/supabase';
import type { ClientContactRow } from '@/lib/dbTypes';

export interface ClientContact {
  id: string;
  clientId: string;
  name: string;
  roleTitle: string | null;
  email: string | null;
  phone: string | null;
  isPrimary: boolean;
}

function toContact(row: ClientContactRow): ClientContact {
  return {
    id: row.id,
    clientId: row.client_id,
    name: row.name,
    roleTitle: row.role_title,
    email: row.email,
    phone: row.phone,
    isPrimary: row.is_primary,
  };
}

async function getContactsForClient(clientId: string): Promise<ClientContact[]> {
  const { data, error } = await supabase.from('client_contacts').select('*').eq('client_id', clientId).order('is_primary', { ascending: false });
  if (error) throw error;
  return data.map(toContact);
}

async function createContact(input: { tenantId: string; clientId: string; name: string; roleTitle?: string; email?: string; phone?: string }): Promise<ClientContact> {
  const { data, error } = await supabase
    .from('client_contacts')
    .insert({ tenant_id: input.tenantId, client_id: input.clientId, name: input.name, role_title: input.roleTitle ?? null, email: input.email ?? null, phone: input.phone ?? null })
    .select('*')
    .single();
  if (error) throw error;
  return toContact(data);
}

export const clientContactService = {
  getContactsForClient,
  createContact,
};
