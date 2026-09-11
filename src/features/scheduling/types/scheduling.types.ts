/**
 * Domain types for the Scheduling feature (shift definitions + shifts).
 * Used only within this feature, so per the type-ownership convention these
 * stay here rather than in the cross-feature src/types/ barrel.
 */

import type { EntityStatus } from '@/features/employees/types/employee.types';

export type { EntityStatus };

export type ShiftStatus = 'scheduled' | 'confirmed' | 'cancelled' | 'completed';

export interface ShiftDefinition {
  id: string;
  tenantId: string;
  name: string;
  /** "HH:MM:SS", tenant-local wall-clock time — see the Phase G date/time strategy (no stored timezone; South Africa only). */
  startTime: string;
  endTime: string;
  isOvernight: boolean;
  breakMinutes: number;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export interface CreateShiftDefinitionInput {
  name: string;
  startTime: string;
  endTime: string;
  isOvernight: boolean;
  breakMinutes: number;
}

export interface UpdateShiftDefinitionInput {
  name?: string;
  startTime?: string;
  endTime?: string;
  isOvernight?: boolean;
  breakMinutes?: number;
  status?: EntityStatus;
}

export interface Shift {
  id: string;
  tenantId: string;
  siteId: string;
  employeeId: string;
  supervisorId: string | null;
  shiftDefinitionId: string | null;
  startsAt: string;
  endsAt: string;
  status: ShiftStatus;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateShiftInput {
  siteId: string;
  employeeId: string;
  supervisorId?: string | null;
  shiftDefinitionId?: string | null;
  startsAt: string;
  endsAt: string;
  notes?: string | null;
}

export interface UpdateShiftInput {
  siteId?: string;
  employeeId?: string;
  supervisorId?: string | null;
  shiftDefinitionId?: string | null;
  startsAt?: string;
  endsAt?: string;
  status?: ShiftStatus;
  notes?: string | null;
}

export interface ShiftsListFilters {
  siteId?: string;
  employeeId?: string;
  /** Inclusive range, ISO timestamps — used to scope a shift query to one week. */
  rangeStart?: string;
  rangeEnd?: string;
}
