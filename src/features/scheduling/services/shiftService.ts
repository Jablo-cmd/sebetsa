import { supabase } from '@/lib/supabase';
import type { ShiftRow } from '@/lib/dbTypes';
import type { Shift, CreateShiftInput, UpdateShiftInput, ShiftsListFilters } from '@/features/scheduling/types/scheduling.types';

function toShift(row: ShiftRow): Shift {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    employeeId: row.employee_id,
    supervisorId: row.supervisor_id,
    shiftDefinitionId: row.shift_definition_id,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    status: row.status,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** Shifts for a tenant, optionally narrowed to a site/employee and a time range — the query the Schedule week grid and My Schedule both use. */
async function getShifts(tenantId: string, filters: ShiftsListFilters = {}): Promise<Shift[]> {
  let query = supabase.from('shifts').select('*').eq('tenant_id', tenantId);

  if (filters.siteId) query = query.eq('site_id', filters.siteId);
  if (filters.employeeId) query = query.eq('employee_id', filters.employeeId);
  // Overlap with [rangeStart, rangeEnd): a shift is in range if it starts
  // before the range ends and ends after the range starts.
  if (filters.rangeEnd) query = query.lt('starts_at', filters.rangeEnd);
  if (filters.rangeStart) query = query.gt('ends_at', filters.rangeStart);

  const { data, error } = await query.order('starts_at', { ascending: true });
  if (error) throw error;
  return data.map(toShift);
}

async function createShift(tenantId: string, input: CreateShiftInput): Promise<Shift> {
  const { data, error } = await supabase
    .from('shifts')
    .insert({
      tenant_id: tenantId,
      site_id: input.siteId,
      employee_id: input.employeeId,
      supervisor_id: input.supervisorId ?? null,
      shift_definition_id: input.shiftDefinitionId ?? null,
      starts_at: input.startsAt,
      ends_at: input.endsAt,
      notes: input.notes ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toShift(data);
}

async function updateShift(id: string, updates: UpdateShiftInput): Promise<Shift> {
  const payload: Record<string, unknown> = {};
  if (updates.siteId !== undefined) payload.site_id = updates.siteId;
  if (updates.employeeId !== undefined) payload.employee_id = updates.employeeId;
  if (updates.supervisorId !== undefined) payload.supervisor_id = updates.supervisorId;
  if (updates.shiftDefinitionId !== undefined) payload.shift_definition_id = updates.shiftDefinitionId;
  if (updates.startsAt !== undefined) payload.starts_at = updates.startsAt;
  if (updates.endsAt !== undefined) payload.ends_at = updates.endsAt;
  if (updates.status !== undefined) payload.status = updates.status;
  if (updates.notes !== undefined) payload.notes = updates.notes;

  const { data, error } = await supabase.from('shifts').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toShift(data);
}

/** Cancels a shift (status update, never a delete — preserves the schedule's history and audit trail). */
async function cancelShift(id: string): Promise<Shift> {
  return updateShift(id, { status: 'cancelled' });
}

export const shiftService = {
  getShifts,
  createShift,
  updateShift,
  cancelShift,
};
