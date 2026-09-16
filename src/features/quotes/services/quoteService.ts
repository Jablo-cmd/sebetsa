import { supabase } from '@/lib/supabase';
import type { QuoteRow, QuoteInsert, QuoteUpdate, QuoteLineItemRow, QuoteLineItemInsert, QuoteLineItemUpdate, ContractRow } from '@/lib/dbTypes';
import type {
  Quote,
  QuoteLineItem,
  CreateQuoteInput,
  UpdateQuoteInput,
  CreateQuoteLineItemInput,
  UpdateQuoteLineItemInput,
  QuotesListFilters,
  QuotesListPage,
} from '@/features/quotes/types/quote.types';
import { toContract } from '@/features/orgStructure/services/contractService';
import type { Contract } from '@/features/orgStructure/types/orgStructure.types';

const DEFAULT_PAGE_SIZE = 20;

export function toQuote(row: QuoteRow): Quote {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    siteId: row.site_id,
    quoteNumber: row.quote_number,
    version: row.version,
    status: row.status,
    expiryDate: row.expiry_date,
    discountAmount: row.discount_amount,
    taxRate: row.tax_rate,
    subtotal: row.subtotal,
    taxAmount: row.tax_amount,
    totalAmount: row.total_amount,
    notes: row.notes,
    assumptions: row.assumptions,
    exclusions: row.exclusions,
    preparedBy: row.prepared_by,
    convertedToContractId: row.converted_to_contract_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function toQuoteLineItem(row: QuoteLineItemRow): QuoteLineItem {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    quoteId: row.quote_id,
    category: row.category,
    description: row.description,
    quantity: row.quantity,
    unitRate: row.unit_rate,
    lineTotal: row.line_total,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getQuotes(
  tenantId: string,
  filters: QuotesListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<QuotesListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('quotes').select('*', { count: 'exact' }).eq('tenant_id', tenantId);

  const term = filters.search?.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.ilike('quote_number', `%${escaped}%`);
  }
  if (filters.clientId) query = query.eq('client_id', filters.clientId);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error, count } = await query.order('created_at', { ascending: false }).range(from, to);
  if (error) throw error;

  return { quotes: data.map(toQuote), totalCount: count ?? 0, page, pageSize };
}

async function getQuote(id: string): Promise<Quote | null> {
  const { data, error } = await supabase.from('quotes').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toQuote(data) : null;
}

/** Every quote for one client, unpaginated — fits a client detail-page section. */
async function getQuotesForClient(clientId: string): Promise<Quote[]> {
  const { data, error } = await supabase.from('quotes').select('*').eq('client_id', clientId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toQuote);
}

function toInsertPayload(tenantId: string, input: CreateQuoteInput): QuoteInsert {
  return {
    tenant_id: tenantId,
    client_id: input.clientId,
    site_id: input.siteId ?? null,
    quote_number: input.quoteNumber,
    expiry_date: input.expiryDate ?? null,
    discount_amount: input.discountAmount ?? undefined,
    tax_rate: input.taxRate ?? undefined,
    notes: input.notes ?? null,
    assumptions: input.assumptions ?? null,
    exclusions: input.exclusions ?? null,
    prepared_by: null,
  };
}

async function createQuote(tenantId: string, input: CreateQuoteInput): Promise<Quote> {
  const { data, error } = await supabase.from('quotes').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toQuote(data);
}

async function updateQuote(id: string, updates: UpdateQuoteInput): Promise<Quote> {
  const payload: QuoteUpdate = {};
  if (updates.clientId !== undefined) payload.client_id = updates.clientId;
  if (updates.siteId !== undefined) payload.site_id = updates.siteId;
  if (updates.quoteNumber !== undefined) payload.quote_number = updates.quoteNumber;
  if (updates.expiryDate !== undefined) payload.expiry_date = updates.expiryDate;
  if (updates.discountAmount !== undefined) payload.discount_amount = updates.discountAmount;
  if (updates.taxRate !== undefined) payload.tax_rate = updates.taxRate;
  if (updates.notes !== undefined) payload.notes = updates.notes;
  if (updates.assumptions !== undefined) payload.assumptions = updates.assumptions;
  if (updates.exclusions !== undefined) payload.exclusions = updates.exclusions;

  const { data, error } = await supabase.from('quotes').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toQuote(data);
}

async function updateQuoteStatus(id: string, status: Quote['status']): Promise<Quote> {
  const { data, error } = await supabase.from('quotes').update({ status }).eq('id', id).select('*').single();
  if (error) throw error;
  return toQuote(data);
}

async function getLineItems(quoteId: string): Promise<QuoteLineItem[]> {
  const { data, error } = await supabase.from('quote_line_items').select('*').eq('quote_id', quoteId).order('sort_order', { ascending: true });
  if (error) throw error;
  return data.map(toQuoteLineItem);
}

function toLineItemInsertPayload(tenantId: string, input: CreateQuoteLineItemInput): QuoteLineItemInsert {
  return {
    tenant_id: tenantId,
    quote_id: input.quoteId,
    category: input.category ?? undefined,
    description: input.description,
    quantity: input.quantity,
    unit_rate: input.unitRate,
    sort_order: input.sortOrder ?? 0,
  };
}

async function addLineItem(tenantId: string, input: CreateQuoteLineItemInput): Promise<QuoteLineItem> {
  const { data, error } = await supabase.from('quote_line_items').insert(toLineItemInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toQuoteLineItem(data);
}

async function updateLineItem(id: string, updates: UpdateQuoteLineItemInput): Promise<QuoteLineItem> {
  const payload: QuoteLineItemUpdate = {};
  if (updates.category !== undefined) payload.category = updates.category;
  if (updates.description !== undefined) payload.description = updates.description;
  if (updates.quantity !== undefined) payload.quantity = updates.quantity;
  if (updates.unitRate !== undefined) payload.unit_rate = updates.unitRate;
  if (updates.sortOrder !== undefined) payload.sort_order = updates.sortOrder;

  const { data, error } = await supabase.from('quote_line_items').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toQuoteLineItem(data);
}

async function removeLineItem(id: string): Promise<void> {
  const { error } = await supabase.from('quote_line_items').delete().eq('id', id);
  if (error) throw error;
}

/** The only way a quote's subtotal/tax/total ever change — always derived server-side from the real line items. */
async function recomputeTotals(quoteId: string): Promise<Quote> {
  const { data, error } = await supabase.rpc('recompute_quote_totals', { p_quote_id: quoteId });
  if (error) throw error;
  return toQuote(data);
}

/** The controlled QUOTE -> CONTRACT boundary. Only an approved, not-yet-converted quote can convert, exactly once. */
async function convertToContract(quoteId: string, contractNumber: string, startDate: string): Promise<Contract> {
  const { data, error } = await supabase.rpc('convert_quote_to_contract', {
    p_quote_id: quoteId,
    p_contract_number: contractNumber,
    p_start_date: startDate,
  });
  if (error) throw error;
  return toContract(data as ContractRow);
}

export const quoteService = {
  getQuotes,
  getQuote,
  getQuotesForClient,
  createQuote,
  updateQuote,
  updateQuoteStatus,
  getLineItems,
  addLineItem,
  updateLineItem,
  removeLineItem,
  recomputeTotals,
  convertToContract,
};
