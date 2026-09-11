import { supabase } from '@/lib/supabase';
import type { ShiftDefinitionRow } from '@/lib/dbTypes';
import type {
  ShiftDefinition,
  CreateShiftDefinitionInput,
  UpdateShiftDefinitionInput,
} from '@/features/scheduling/types/scheduling.types';

function toShiftDefinition(row: ShiftDefinitionRow): ShiftDefinition {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    startTime: row.start_time,
    endTime: row.end_time,
    isOvernight: row.is_overnight,
    breakMinutes: row.break_minutes,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getShiftDefinitions(tenantId: string): Promise<ShiftDefinition[]> {
  const { data, error } = await supabase
    .from('shift_definitions')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toShiftDefinition);
}

async function createShiftDefinition(tenantId: string, input: CreateShiftDefinitionInput): Promise<ShiftDefinition> {
  const { data, error } = await supabase
    .from('shift_definitions')
    .insert({
      tenant_id: tenantId,
      name: input.name,
      start_time: input.startTime,
      end_time: input.endTime,
      is_overnight: input.isOvernight,
      break_minutes: input.breakMinutes,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toShiftDefinition(data);
}

async function updateShiftDefinition(id: string, updates: UpdateShiftDefinitionInput): Promise<ShiftDefinition> {
  const payload: Record<string, unknown> = {};
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.startTime !== undefined) payload.start_time = updates.startTime;
  if (updates.endTime !== undefined) payload.end_time = updates.endTime;
  if (updates.isOvernight !== undefined) payload.is_overnight = updates.isOvernight;
  if (updates.breakMinutes !== undefined) payload.break_minutes = updates.breakMinutes;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('shift_definitions').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toShiftDefinition(data);
}

async function archiveShiftDefinition(id: string): Promise<ShiftDefinition> {
  return updateShiftDefinition(id, { status: 'inactive' });
}

async function restoreShiftDefinition(id: string): Promise<ShiftDefinition> {
  return updateShiftDefinition(id, { status: 'active' });
}

export const shiftDefinitionService = {
  getShiftDefinitions,
  createShiftDefinition,
  updateShiftDefinition,
  archiveShiftDefinition,
  restoreShiftDefinition,
};
