import { supabase } from '@/lib/supabase';
import type { LeaveBalanceRow, LeaveBalanceTransactionRow } from '@/lib/dbTypes';
import type { LeaveBalance, LeaveBalanceTransaction } from '@/features/leave/types/leave.types';

function toLeaveBalance(row: LeaveBalanceRow): LeaveBalance {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    leaveTypeId: row.leave_type_id,
    periodYear: row.period_year,
    openingBalance: row.opening_balance,
    accrued: row.accrued,
    used: row.used,
    pending: row.pending,
    adjustment: row.adjustment,
    carriedOver: row.carried_over,
    remaining: row.remaining,
  };
}

function toLeaveBalanceTransaction(row: LeaveBalanceTransactionRow): LeaveBalanceTransaction {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    leaveTypeId: row.leave_type_id,
    periodYear: row.period_year,
    transactionType: row.transaction_type as LeaveBalanceTransaction['transactionType'],
    amount: row.amount,
    leaveRequestId: row.leave_request_id,
    createdBy: row.created_by,
    createdAt: row.created_at,
  };
}

async function getBalances(tenantId: string, filters: { employeeId?: string; periodYear?: number } = {}): Promise<LeaveBalance[]> {
  let query = supabase.from('leave_balances').select('*').eq('tenant_id', tenantId);
  if (filters.employeeId) query = query.eq('employee_id', filters.employeeId);
  if (filters.periodYear) query = query.eq('period_year', filters.periodYear);
  const { data, error } = await query;
  if (error) throw error;
  return data.map(toLeaveBalance);
}

async function getLedger(employeeId: string, leaveTypeId: string, periodYear: number): Promise<LeaveBalanceTransaction[]> {
  const { data, error } = await supabase
    .from('leave_balance_transactions')
    .select('*')
    .eq('employee_id', employeeId)
    .eq('leave_type_id', leaveTypeId)
    .eq('period_year', periodYear)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toLeaveBalanceTransaction);
}

async function adjustBalance(
  employeeId: string,
  leaveTypeId: string,
  periodYear: number,
  amount: number,
  note?: string,
): Promise<LeaveBalance> {
  const { data, error } = await supabase.rpc('adjust_leave_balance', {
    p_employee_id: employeeId,
    p_leave_type_id: leaveTypeId,
    p_period_year: periodYear,
    p_amount: amount,
    p_note: note ?? undefined,
  });
  if (error) throw error;
  return toLeaveBalance(data);
}

async function recomputeBalance(employeeId: string, leaveTypeId: string, periodYear: number): Promise<LeaveBalance> {
  const { data, error } = await supabase.rpc('recompute_leave_balance', {
    p_employee_id: employeeId,
    p_leave_type_id: leaveTypeId,
    p_period_year: periodYear,
  });
  if (error) throw error;
  return toLeaveBalance(data);
}

export const leaveBalanceService = {
  getBalances,
  getLedger,
  adjustBalance,
  recomputeBalance,
};
