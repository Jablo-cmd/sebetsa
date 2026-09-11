import type { Database } from '@/lib/database.types';

export type EntityStatus = Database['public']['Enums']['entity_status'];

export interface Team {
  id: string;
  tenantId: string;
  siteId: string | null;
  name: string;
  leadEmployeeId: string | null;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateTeamInput {
  name: string;
  siteId?: string | null;
  leadEmployeeId?: string | null;
}

export interface UpdateTeamInput {
  name?: string;
  siteId?: string | null;
  leadEmployeeId?: string | null;
  status?: EntityStatus;
}

export interface TeamMember {
  teamId: string;
  employeeId: string;
  tenantId: string;
  joinedAt: string;
  employeeFirstName: string;
  employeeLastName: string;
  employeeNumber: string;
}
