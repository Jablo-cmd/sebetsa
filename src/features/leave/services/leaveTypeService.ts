import { supabase } from '@/lib/supabase';
import type { LeaveTypeRow, LeavePolicyRow } from '@/lib/dbTypes';
import type { LeaveType, LeavePolicy } from '@/features/leave/types/leave.types';

function toLeaveType(row: LeaveTypeRow): LeaveType {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    isPaid: row.is_paid,
    requiresDocumentation: row.requires_documentation,
    defaultAnnualDays: row.default_annual_days,
    status: row.status,
  };
}

function toLeavePolicy(row: LeavePolicyRow): LeavePolicy {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    leaveTypeId: row.leave_type_id,
    defaultAnnualDays: row.default_annual_days,
    maxCarryOverDays: row.max_carry_over_days,
    minNoticeDays: row.min_notice_days,
    requiresDocumentation: row.requires_documentation,
    maxConsecutiveDays: row.max_consecutive_days,
  };
}

async function getLeaveTypes(tenantId: string, includeInactive = false): Promise<LeaveType[]> {
  let query = supabase.from('leave_types').select('*').eq('tenant_id', tenantId);
  if (!includeInactive) query = query.eq('status', 'active');
  const { data, error } = await query.order('name', { ascending: true });
  if (error) throw error;
  return data.map(toLeaveType);
}

async function createLeaveType(
  tenantId: string,
  input: { name: string; isPaid: boolean; requiresDocumentation: boolean; defaultAnnualDays: number | null },
): Promise<LeaveType> {
  const { data, error } = await supabase
    .from('leave_types')
    .insert({
      tenant_id: tenantId,
      name: input.name,
      is_paid: input.isPaid,
      requires_documentation: input.requiresDocumentation,
      default_annual_days: input.defaultAnnualDays,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toLeaveType(data);
}

async function setLeaveTypeStatus(id: string, status: 'active' | 'inactive'): Promise<LeaveType> {
  const { data, error } = await supabase.from('leave_types').update({ status }).eq('id', id).select('*').single();
  if (error) throw error;
  return toLeaveType(data);
}

async function getLeavePolicies(tenantId: string): Promise<LeavePolicy[]> {
  const { data, error } = await supabase.from('leave_policies').select('*').eq('tenant_id', tenantId);
  if (error) throw error;
  return data.map(toLeavePolicy);
}

async function upsertLeavePolicy(
  tenantId: string,
  leaveTypeId: string,
  input: {
    defaultAnnualDays: number | null;
    maxCarryOverDays: number | null;
    minNoticeDays: number;
    requiresDocumentation: boolean;
    maxConsecutiveDays: number | null;
  },
): Promise<LeavePolicy> {
  const { data, error } = await supabase
    .from('leave_policies')
    .upsert(
      {
        tenant_id: tenantId,
        leave_type_id: leaveTypeId,
        default_annual_days: input.defaultAnnualDays,
        max_carry_over_days: input.maxCarryOverDays,
        min_notice_days: input.minNoticeDays,
        requires_documentation: input.requiresDocumentation,
        max_consecutive_days: input.maxConsecutiveDays,
      },
      { onConflict: 'tenant_id,leave_type_id' },
    )
    .select('*')
    .single();
  if (error) throw error;
  return toLeavePolicy(data);
}

export const leaveTypeService = {
  getLeaveTypes,
  createLeaveType,
  setLeaveTypeStatus,
  getLeavePolicies,
  upsertLeavePolicy,
};
