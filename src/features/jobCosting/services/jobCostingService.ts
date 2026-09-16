import { supabase } from '@/lib/supabase';

export interface ContractProfitability {
  revenue: number;
  labourCost: number;
  consumablesCost: number;
  equipmentCost: number;
  otherCost: number;
  grossContribution: number;
  grossMarginPct: number | null;
}

/** Revenue - Labour - Consumables - Equipment - Other = Gross Contribution; margin% is null (never a misleading zero) when revenue is zero. Every figure is a real aggregate over invoices/attendance_records/inventory_movements/cost_entries — never a fabricated percentage. */
async function getContractProfitability(contractId: string, periodStart: string, periodEnd: string): Promise<ContractProfitability | null> {
  const { data, error } = await supabase.rpc('get_contract_profitability', {
    p_contract_id: contractId,
    p_period_start: periodStart,
    p_period_end: periodEnd,
  });
  if (error) throw error;
  const row = data?.[0];
  if (!row) return null;
  return {
    revenue: row.revenue,
    labourCost: row.labour_cost,
    consumablesCost: row.consumables_cost,
    equipmentCost: row.equipment_cost,
    otherCost: row.other_cost,
    grossContribution: row.gross_contribution,
    grossMarginPct: row.gross_margin_pct,
  };
}

async function addCostEntry(tenantId: string, contractId: string, siteId: string, category: 'equipment' | 'other', description: string, amount: number, costDate: string): Promise<void> {
  const { error } = await supabase.from('cost_entries').insert({
    tenant_id: tenantId,
    contract_id: contractId,
    site_id: siteId,
    category,
    description,
    amount,
    cost_date: costDate,
  });
  if (error) throw error;
}

export const jobCostingService = {
  getContractProfitability,
  addCostEntry,
};
