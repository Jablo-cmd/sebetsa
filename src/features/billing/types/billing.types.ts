import type { Database } from '@/lib/database.types';

export type InvoiceStatus = Database['public']['Enums']['invoice_status'];
export type InvoiceSource = Database['public']['Enums']['invoice_source'];

export interface Invoice {
  id: string;
  tenantId: string;
  clientId: string;
  contractId: string | null;
  siteId: string | null;
  variationOrderId: string | null;
  invoiceNumber: string;
  source: InvoiceSource;
  billingPeriodStart: string | null;
  billingPeriodEnd: string | null;
  status: InvoiceStatus;
  currency: string;
  taxRate: number;
  subtotal: number;
  taxAmount: number;
  totalAmount: number;
  amountPaid: number;
  amountOutstanding: number;
  issueDate: string | null;
  dueDate: string | null;
  notes: string | null;
  voidReason: string | null;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface InvoiceLine {
  id: string;
  tenantId: string;
  invoiceId: string;
  description: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export interface Payment {
  id: string;
  tenantId: string;
  invoiceId: string;
  amount: number;
  paymentDate: string;
  method: string | null;
  reference: string | null;
  notes: string | null;
  recordedBy: string | null;
  createdAt: string;
}

export interface CreateDraftInvoiceInput {
  clientId: string;
  contractId?: string | null;
  siteId?: string | null;
  taxRate?: number;
  notes?: string | null;
}

export interface CreateInvoiceLineInput {
  invoiceId: string;
  description: string;
  quantity: number;
  unitPrice: number;
  sortOrder?: number;
}
