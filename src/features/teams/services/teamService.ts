import { supabase } from '@/lib/supabase';
import type { TeamRow } from '@/lib/dbTypes';
import type { Team, CreateTeamInput, UpdateTeamInput, TeamMember } from '@/features/teams/types/team.types';

export function toTeam(row: TeamRow): Team {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    name: row.name,
    leadEmployeeId: row.lead_employee_id,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getTeams(tenantId: string): Promise<Team[]> {
  const { data, error } = await supabase
    .from('teams')
    .select('*')
    .eq('tenant_id', tenantId)
    .order('name', { ascending: true });
  if (error) throw error;
  return data.map(toTeam);
}

async function getTeam(id: string): Promise<Team | null> {
  const { data, error } = await supabase.from('teams').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toTeam(data) : null;
}

async function createTeam(tenantId: string, input: CreateTeamInput): Promise<Team> {
  const { data, error } = await supabase
    .from('teams')
    .insert({
      tenant_id: tenantId,
      name: input.name,
      site_id: input.siteId ?? null,
      lead_employee_id: input.leadEmployeeId ?? null,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toTeam(data);
}

async function updateTeam(id: string, updates: UpdateTeamInput): Promise<Team> {
  const payload: Record<string, unknown> = {};
  if (updates.name !== undefined) payload.name = updates.name;
  if (updates.siteId !== undefined) payload.site_id = updates.siteId;
  if (updates.leadEmployeeId !== undefined) payload.lead_employee_id = updates.leadEmployeeId;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('teams').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toTeam(data);
}

async function archiveTeam(id: string): Promise<Team> {
  return updateTeam(id, { status: 'inactive' });
}

async function restoreTeam(id: string): Promise<Team> {
  return updateTeam(id, { status: 'active' });
}

interface TeamMemberJoinRow {
  team_id: string;
  employee_id: string;
  tenant_id: string;
  joined_at: string;
  employee: { first_name: string; last_name: string; employee_number: string } | null;
}

function toTeamMember(row: TeamMemberJoinRow): TeamMember {
  return {
    teamId: row.team_id,
    employeeId: row.employee_id,
    tenantId: row.tenant_id,
    joinedAt: row.joined_at,
    employeeFirstName: row.employee?.first_name ?? '',
    employeeLastName: row.employee?.last_name ?? '',
    employeeNumber: row.employee?.employee_number ?? '',
  };
}

async function getTeamMembers(teamId: string): Promise<TeamMember[]> {
  const { data, error } = await supabase
    .from('team_members')
    .select('team_id, employee_id, tenant_id, joined_at, employee:employees(first_name, last_name, employee_number)')
    .eq('team_id', teamId)
    .order('joined_at', { ascending: true });
  if (error) throw error;
  return (data as unknown as TeamMemberJoinRow[]).map(toTeamMember);
}

/** Every team an employee currently belongs to — for the employee detail page's relationship section. */
async function getTeamsForEmployee(employeeId: string): Promise<Team[]> {
  const { data, error } = await supabase
    .from('team_members')
    .select('team:teams(*)')
    .eq('employee_id', employeeId);
  if (error) throw error;
  return data
    .map((row) => row.team)
    .filter((team): team is NonNullable<typeof team> => team !== null)
    .map(toTeam);
}

async function addTeamMember(tenantId: string, teamId: string, employeeId: string): Promise<void> {
  const { error } = await supabase.from('team_members').insert({ tenant_id: tenantId, team_id: teamId, employee_id: employeeId });
  if (error) throw error;
}

async function removeTeamMember(teamId: string, employeeId: string): Promise<void> {
  const { error } = await supabase.from('team_members').delete().eq('team_id', teamId).eq('employee_id', employeeId);
  if (error) throw error;
}

export const teamService = {
  getTeams,
  getTeam,
  createTeam,
  updateTeam,
  archiveTeam,
  restoreTeam,
  getTeamMembers,
  getTeamsForEmployee,
  addTeamMember,
  removeTeamMember,
};
