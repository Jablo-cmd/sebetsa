import { supabase } from '@/lib/supabase';
import type { EmployeeAvailabilityRow, EmployeeAvailabilityExceptionRow } from '@/lib/dbTypes';
import type {
  AvailabilityWindow,
  CreateAvailabilityWindowInput,
  AvailabilityException,
  CreateAvailabilityExceptionInput,
} from '@/features/availability/types/availability.types';

function toWindow(row: EmployeeAvailabilityRow): AvailabilityWindow {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    dayOfWeek: row.day_of_week as AvailabilityWindow['dayOfWeek'],
    startTime: row.start_time,
    endTime: row.end_time,
  };
}

function toException(row: EmployeeAvailabilityExceptionRow): AvailabilityException {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    exceptionDate: row.exception_date,
    isAvailable: row.is_available,
    startTime: row.start_time,
    endTime: row.end_time,
    reason: row.reason,
    createdAt: row.created_at,
  };
}

async function getWindows(employeeId: string): Promise<AvailabilityWindow[]> {
  const { data, error } = await supabase
    .from('employee_availability')
    .select('*')
    .eq('employee_id', employeeId)
    .order('day_of_week', { ascending: true })
    .order('start_time', { ascending: true });
  if (error) throw error;
  return data.map(toWindow);
}

async function createWindow(tenantId: string, input: CreateAvailabilityWindowInput): Promise<AvailabilityWindow> {
  const { data, error } = await supabase
    .from('employee_availability')
    .insert({
      tenant_id: tenantId,
      employee_id: input.employeeId,
      day_of_week: input.dayOfWeek,
      start_time: input.startTime,
      end_time: input.endTime,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toWindow(data);
}

async function deleteWindow(id: string): Promise<void> {
  const { error } = await supabase.from('employee_availability').delete().eq('id', id);
  if (error) throw error;
}

/** Exceptions from today onward — past exceptions are historical noise for the editor, not something anyone needs to manage. */
async function getUpcomingExceptions(employeeId: string): Promise<AvailabilityException[]> {
  const todayIso = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from('employee_availability_exceptions')
    .select('*')
    .eq('employee_id', employeeId)
    .gte('exception_date', todayIso)
    .order('exception_date', { ascending: true });
  if (error) throw error;
  return data.map(toException);
}

async function createException(tenantId: string, input: CreateAvailabilityExceptionInput): Promise<AvailabilityException> {
  const { data, error } = await supabase
    .from('employee_availability_exceptions')
    .insert({
      tenant_id: tenantId,
      employee_id: input.employeeId,
      exception_date: input.exceptionDate,
      is_available: input.isAvailable,
      start_time: input.startTime ?? null,
      end_time: input.endTime ?? null,
      reason: input.reason ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toException(data);
}

async function deleteException(id: string): Promise<void> {
  const { error } = await supabase.from('employee_availability_exceptions').delete().eq('id', id);
  if (error) throw error;
}

export const availabilityService = {
  getWindows,
  createWindow,
  deleteWindow,
  getUpcomingExceptions,
  createException,
  deleteException,
};
