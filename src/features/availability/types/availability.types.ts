/**
 * Domain types for the Availability feature (employee_availability +
 * employee_availability_exceptions). Used only within this feature.
 */

/** 0 = Sunday, matching the DB's day_of_week convention and JS Date#getDay(). */
export type DayOfWeek = 0 | 1 | 2 | 3 | 4 | 5 | 6;

export interface AvailabilityWindow {
  id: string;
  tenantId: string;
  employeeId: string;
  dayOfWeek: DayOfWeek;
  startTime: string;
  endTime: string;
}

export interface CreateAvailabilityWindowInput {
  employeeId: string;
  dayOfWeek: DayOfWeek;
  startTime: string;
  endTime: string;
}

export interface AvailabilityException {
  id: string;
  tenantId: string;
  employeeId: string;
  exceptionDate: string;
  isAvailable: boolean;
  startTime: string | null;
  endTime: string | null;
  reason: string | null;
  createdAt: string;
}

export interface CreateAvailabilityExceptionInput {
  employeeId: string;
  exceptionDate: string;
  isAvailable: boolean;
  startTime?: string | null;
  endTime?: string | null;
  reason?: string | null;
}
