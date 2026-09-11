import { supabase } from '@/lib/supabase';
import type { PositionRow } from '@/lib/dbTypes';
import type { Position, CreatePositionInput, UpdatePositionInput } from '@/features/employees/types/employee.types';

export function toPosition(row: PositionRow): Position {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    departmentId: row.department_id,
    title: row.title,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getPositions(tenantId: string): Promise<Position[]> {
  const { data, error } = await supabase
    .from('positions')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('title', { ascending: true });
  if (error) throw error;
  return data.map(toPosition);
}

async function getPosition(id: string): Promise<Position | null> {
  const { data, error } = await supabase.from('positions').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toPosition(data) : null;
}

async function createPosition(tenantId: string, input: CreatePositionInput): Promise<Position> {
  const { data, error } = await supabase
    .from('positions')
    .insert({ tenant_id: tenantId, title: input.title, department_id: input.departmentId ?? null })
    .select('*')
    .single();
  if (error) throw error;
  return toPosition(data);
}

async function updatePosition(id: string, updates: UpdatePositionInput): Promise<Position> {
  const payload: Record<string, unknown> = {};
  if (updates.title !== undefined) payload.title = updates.title;
  if (updates.departmentId !== undefined) payload.department_id = updates.departmentId;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('positions').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toPosition(data);
}

async function archivePosition(id: string): Promise<Position> {
  return updatePosition(id, { status: 'inactive' });
}

async function restorePosition(id: string): Promise<Position> {
  return updatePosition(id, { status: 'active' });
}

export const positionService = {
  getPositions,
  getPosition,
  createPosition,
  updatePosition,
  archivePosition,
  restorePosition,
};
