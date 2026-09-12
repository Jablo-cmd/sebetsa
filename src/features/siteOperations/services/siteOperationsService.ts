import { supabase } from '@/lib/supabase';
import type { SiteStaffingRequirementRow } from '@/lib/dbTypes';
import type { SiteWorkforceOverview, StaffingRequirement } from '@/features/siteOperations/types/siteOperations.types';

function toStaffingRequirement(row: SiteStaffingRequirementRow): StaffingRequirement {
  return { id: row.id, tenantId: row.tenant_id, siteId: row.site_id, label: row.label, requiredCount: row.required_count };
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Aggregate operational visibility for one site — a handful of indexed
 * COUNT queries against tables that already carry their own RLS, run in
 * parallel. Deliberately not a database VIEW (see the migration's own
 * comment: a view here would be owned by a superuser role and would
 * bypass RLS even with FORCE ROW LEVEL SECURITY set).
 */
async function getSiteWorkforceOverview(tenantId: string, siteId: string): Promise<SiteWorkforceOverview> {
  const today = todayIso();
  const dayStart = `${today}T00:00:00`;
  const dayEnd = `${today}T23:59:59.999`;

  const [assigned, scheduledToday, present, late, absent, openTasks, requirements] = await Promise.all([
    supabase
      .from('site_assignments')
      .select('*', { count: 'exact', head: true })
      .eq('site_id', siteId)
      .or(`end_date.is.null,end_date.gte.${today}`),
    supabase
      .from('shifts')
      .select('*', { count: 'exact', head: true })
      .eq('site_id', siteId)
      .neq('status', 'cancelled')
      .gte('starts_at', dayStart)
      .lte('starts_at', dayEnd),
    supabase
      .from('attendance_records')
      .select('*', { count: 'exact', head: true })
      .eq('site_id', siteId)
      .eq('status', 'present')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd),
    supabase
      .from('attendance_records')
      .select('*', { count: 'exact', head: true })
      .eq('site_id', siteId)
      .eq('status', 'late')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd),
    supabase
      .from('attendance_records')
      .select('*', { count: 'exact', head: true })
      .eq('site_id', siteId)
      .eq('status', 'absent')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd),
    supabase.from('tasks').select('*', { count: 'exact', head: true }).eq('site_id', siteId).in('status', ['open', 'in_progress']),
    supabase.from('site_staffing_requirements').select('required_count').eq('tenant_id', tenantId).eq('site_id', siteId),
  ]);

  for (const result of [assigned, scheduledToday, present, late, absent, openTasks, requirements]) {
    if (result.error) throw result.error;
  }

  const requiredCount = requirements.data && requirements.data.length > 0
    ? requirements.data.reduce((sum, row) => sum + row.required_count, 0)
    : null;

  return {
    siteId,
    assignedCount: assigned.count ?? 0,
    scheduledTodayCount: scheduledToday.count ?? 0,
    presentCount: present.count ?? 0,
    lateCount: late.count ?? 0,
    absentCount: absent.count ?? 0,
    openTasksCount: openTasks.count ?? 0,
    requiredCount,
  };
}

async function getStaffingRequirements(tenantId: string, siteId: string): Promise<StaffingRequirement[]> {
  const { data, error } = await supabase.from('site_staffing_requirements').select('*').eq('tenant_id', tenantId).eq('site_id', siteId);
  if (error) throw error;
  return data.map(toStaffingRequirement);
}

async function upsertStaffingRequirement(tenantId: string, siteId: string, label: string, requiredCount: number): Promise<StaffingRequirement> {
  const { data, error } = await supabase
    .from('site_staffing_requirements')
    .upsert({ tenant_id: tenantId, site_id: siteId, label, required_count: requiredCount }, { onConflict: 'tenant_id,site_id,label' })
    .select('*')
    .single();
  if (error) throw error;
  return toStaffingRequirement(data);
}

export const siteOperationsService = {
  getSiteWorkforceOverview,
  getStaffingRequirements,
  upsertStaffingRequirement,
};
