import { supabase } from '@/lib/supabase';
import type { InvoiceRow, InvoiceLineRow, PaymentRow } from '@/lib/dbTypes';
import type { Invoice, InvoiceLine, Payment, CreateDraftInvoiceInput, CreateInvoiceLineInput } from '@/features/billing/types/billing.types';

export function toInvoice(row: InvoiceRow): Invoice {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    contractId: row.contract_id,
    siteId: row.site_id,
    variationOrderId: row.variation_order_id,
    invoiceNumber: row.invoice_number,
    source: row.source,
    billingPeriodStart: row.billing_period_start,
    billingPeriodEnd: row.billing_period_end,
    status: row.status,
    currency: row.currency,
    taxRate: row.tax_rate,
    subtotal: row.subtotal,
    taxAmount: row.tax_amount,
    totalAmount: row.total_amount,
    amountPaid: row.amount_paid,
    amountOutstanding: row.amount_outstanding,
    issueDate: row.issue_date,
    dueDate: row.due_date,
    notes: row.notes,
    voidReason: row.void_reason,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toInvoiceLine(row: InvoiceLineRow): InvoiceLine {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    invoiceId: row.invoice_id,
    description: row.description,
    quantity: row.quantity,
    unitPrice: row.unit_price,
    lineTotal: row.line_total,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toPayment(row: PaymentRow): Payment {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    invoiceId: row.invoice_id,
    amount: row.amount,
    paymentDate: row.payment_date,
    method: row.method,
    reference: row.reference,
    notes: row.notes,
    recordedBy: row.recorded_by,
    createdAt: row.created_at,
  };
}

async function getInvoices(tenantId: string): Promise<Invoice[]> {
  const { data, error } = await supabase.from('invoices').select('*').eq('tenant_id', tenantId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toInvoice);
}

async function getInvoicesForClient(clientId: string): Promise<Invoice[]> {
  const { data, error } = await supabase.from('invoices').select('*').eq('client_id', clientId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toInvoice);
}

async function getInvoice(id: string): Promise<Invoice | null> {
  const { data, error } = await supabase.from('invoices').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toInvoice(data) : null;
}

async function getInvoiceLines(invoiceId: string): Promise<InvoiceLine[]> {
  const { data, error } = await supabase.from('invoice_lines').select('*').eq('invoice_id', invoiceId).order('sort_order', { ascending: true });
  if (error) throw error;
  return data.map(toInvoiceLine);
}

async function getPayments(invoiceId: string): Promise<Payment[]> {
  const { data, error } = await supabase.from('payments').select('*').eq('invoice_id', invoiceId).order('payment_date', { ascending: false });
  if (error) throw error;
  return data.map(toPayment);
}

/** The manual-invoice path — invoices has no direct client INSERT policy, so this RPC (and the two generators below) are the only ways to create a row. */
async function createDraftInvoice(input: CreateDraftInvoiceInput): Promise<Invoice> {
  const { data, error } = await supabase.rpc('create_draft_invoice', {
    p_client_id: input.clientId,
    p_contract_id: input.contractId ?? null,
    p_site_id: input.siteId ?? null,
    p_tax_rate: input.taxRate ?? 15,
    p_notes: input.notes ?? null,
  });
  if (error) throw error;
  return toInvoice(data);
}

async function addInvoiceLine(tenantId: string, input: CreateInvoiceLineInput): Promise<InvoiceLine> {
  const { data, error } = await supabase
    .from('invoice_lines')
    .insert({
      tenant_id: tenantId,
      invoice_id: input.invoiceId,
      description: input.description,
      quantity: input.quantity,
      unit_price: input.unitPrice,
      sort_order: input.sortOrder ?? 0,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toInvoiceLine(data);
}

/** The only way subtotal/tax/total ever change — always derived server-side from the real invoice_lines rows. */
async function recomputeTotals(invoiceId: string): Promise<Invoice> {
  const { data, error } = await supabase.rpc('recompute_invoice_totals', { p_invoice_id: invoiceId });
  if (error) throw error;
  return toInvoice(data);
}

async function issueInvoice(invoiceId: string, issueDate: string, dueDate: string): Promise<Invoice> {
  const { data, error } = await supabase.rpc('issue_invoice', { p_invoice_id: invoiceId, p_issue_date: issueDate, p_due_date: dueDate });
  if (error) throw error;
  return toInvoice(data);
}

async function voidInvoice(invoiceId: string, reason: string): Promise<Invoice> {
  const { data, error } = await supabase.rpc('void_invoice', { p_invoice_id: invoiceId, p_reason: reason });
  if (error) throw error;
  return toInvoice(data);
}

/** Payment RECORDING only — no payment gateway. Rejects overpayment beyond the current outstanding balance server-side. */
async function recordPayment(invoiceId: string, amount: number, paymentDate: string, method?: string, reference?: string, notes?: string): Promise<Invoice> {
  const { data, error } = await supabase.rpc('record_payment', {
    p_invoice_id: invoiceId,
    p_amount: amount,
    p_payment_date: paymentDate,
    p_method: method ?? null,
    p_reference: reference ?? null,
    p_notes: notes ?? null,
  });
  if (error) throw error;
  return toInvoice(data);
}

/** Bills a real recurring-contract billing period from the contract's own persisted commercial terms. */
async function generateContractBillingInvoice(contractId: string, periodStart: string, periodEnd: string): Promise<Invoice> {
  const { data, error } = await supabase.rpc('generate_contract_billing_invoice', {
    p_contract_id: contractId,
    p_billing_period_start: periodStart,
    p_billing_period_end: periodEnd,
  });
  if (error) throw error;
  return toInvoice(data);
}

export const billingService = {
  getInvoices,
  getInvoicesForClient,
  getInvoice,
  getInvoiceLines,
  getPayments,
  createDraftInvoice,
  addInvoiceLine,
  recomputeTotals,
  issueInvoice,
  voidInvoice,
  recordPayment,
  generateContractBillingInvoice,
};
