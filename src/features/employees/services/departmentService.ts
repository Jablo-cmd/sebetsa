import { supabase } from '@/lib/supabase';
import type { DepartmentRow } from '@/lib/dbTypes';
import type { Department, CreateDepartmentInput, UpdateDepartmentInput } from '@/features/employees/types/employee.types';

/** Exported so employeeService can reuse it instead of re-declaring its own mapper. */
export function toDepartment(row: DepartmentRow): Department {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getDepartments(tenantId: string): Promise<Department[]> {
  const { data, error } = await supabase
    .from('departments')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toDepartment);
}

async function getDepartment(id: string): Promise<Department | null> {
  const { data, error } = await supabase.from('departments').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toDepartment(data) : null;
}

async function createDepartment(tenantId: string, input: CreateDepartmentInput): Promise<Department> {
  const { data, error } = await supabase
    .from('departments')
    .insert({ tenant_id: tenantId, name: input.name })
    .select('*')
    .single();
  if (error) throw error;
  return toDepartment(data);
}

async function updateDepartment(id: string, updates: UpdateDepartmentInput): Promise<Department> {
  const { data, error } = await supabase
    .from('departments')
    .update({ name: updates.name })
    .eq('id', id)
    .select('*')
    .single();
  if (error) throw error;
  return toDepartment(data);
}

async function deleteDepartment(id: string): Promise<void> {
  const { error } = await supabase.from('departments').delete().eq('id', id);
  if (error) throw error;
}

export const departmentService = {
  getDepartments,
  getDepartment,
  createDepartment,
  updateDepartment,
  deleteDepartment,
};
