import type { Database } from '@/lib/database.types';

export type QuoteStatus = Database['public']['Enums']['quote_status'];
export type QuoteLineCategory = Database['public']['Enums']['quote_line_category'];

export interface Quote {
  id: string;
  tenantId: string;
  clientId: string;
  siteId: string | null;
  quoteNumber: string;
  version: number;
  status: QuoteStatus;
  expiryDate: string | null;
  discountAmount: number;
  taxRate: number;
  subtotal: number;
  taxAmount: number;
  totalAmount: number;
  notes: string | null;
  assumptions: string | null;
  exclusions: string | null;
  preparedBy: string | null;
  convertedToContractId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateQuoteInput {
  clientId: string;
  siteId?: string | null;
  quoteNumber: string;
  expiryDate?: string | null;
  discountAmount?: number;
  taxRate?: number;
  notes?: string | null;
  assumptions?: string | null;
  exclusions?: string | null;
}

export type UpdateQuoteInput = Partial<CreateQuoteInput>;

export interface QuotesListFilters {
  search?: string;
  clientId?: string;
  status?: QuoteStatus;
}

export interface QuotesListPage {
  quotes: Quote[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface QuoteLineItem {
  id: string;
  tenantId: string;
  quoteId: string;
  category: QuoteLineCategory;
  description: string;
  quantity: number;
  unitRate: number;
  lineTotal: number;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export interface CreateQuoteLineItemInput {
  quoteId: string;
  category?: QuoteLineCategory;
  description: string;
  quantity: number;
  unitRate: number;
  sortOrder?: number;
}

export type UpdateQuoteLineItemInput = Partial<Omit<CreateQuoteLineItemInput, 'quoteId'>>;
