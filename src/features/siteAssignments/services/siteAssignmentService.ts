import { supabase } from '@/lib/supabase';
import type { SiteAssignmentRow } from '@/lib/dbTypes';
import type {
  SiteAssignment,
  CreateSiteAssignmentInput,
  UpdateSiteAssignmentInput,
  SiteAssignmentsListFilters,
} from '@/features/siteAssignments/types/siteAssignment.types';

function toSiteAssignment(row: SiteAssignmentRow): SiteAssignment {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    employeeId: row.employee_id,
    roleOnSite: row.role_on_site,
    startDate: row.start_date,
    endDate: row.end_date,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

async function getSiteAssignments(tenantId: string, filters: SiteAssignmentsListFilters = {}): Promise<SiteAssignment[]> {
  let query = supabase.from('site_assignments').select('*').eq('tenant_id', tenantId);

  if (filters.siteId) query = query.eq('site_id', filters.siteId);
  if (filters.employeeId) query = query.eq('employee_id', filters.employeeId);
  if (filters.when === 'current') query = query.or(`end_date.is.null,end_date.gte.${todayIso()}`);
  if (filters.when === 'historical') query = query.lt('end_date', todayIso());

  const { data, error } = await query.order('start_date', { ascending: false });
  if (error) throw error;
  return data.map(toSiteAssignment);
}

async function getSiteAssignment(id: string): Promise<SiteAssignment | null> {
  const { data, error } = await supabase.from('site_assignments').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toSiteAssignment(data) : null;
}

async function createSiteAssignment(tenantId: string, input: CreateSiteAssignmentInput): Promise<SiteAssignment> {
  const { data, error } = await supabase
    .from('site_assignments')
    .insert({
      tenant_id: tenantId,
      site_id: input.siteId,
      employee_id: input.employeeId,
      role_on_site: input.roleOnSite ?? null,
      start_date: input.startDate,
      end_date: input.endDate ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toSiteAssignment(data);
}

async function updateSiteAssignment(id: string, updates: UpdateSiteAssignmentInput): Promise<SiteAssignment> {
  const payload: Record<string, unknown> = {};
  if (updates.siteId !== undefined) payload.site_id = updates.siteId;
  if (updates.employeeId !== undefined) payload.employee_id = updates.employeeId;
  if (updates.roleOnSite !== undefined) payload.role_on_site = updates.roleOnSite;
  if (updates.startDate !== undefined) payload.start_date = updates.startDate;
  if (updates.endDate !== undefined) payload.end_date = updates.endDate;

  const { data, error } = await supabase.from('site_assignments').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toSiteAssignment(data);
}

/** Ends an assignment as of today (or an explicit date) rather than deleting it — historical assignments stay visible. */
async function endAssignment(id: string, endDate: string = todayIso()): Promise<SiteAssignment> {
  return updateSiteAssignment(id, { endDate });
}

export const siteAssignmentService = {
  getSiteAssignments,
  getSiteAssignment,
  createSiteAssignment,
  updateSiteAssignment,
  endAssignment,
};
