import type { Database } from '@/lib/database.types';

export type EmploymentType = Database['public']['Enums']['employment_type'];
export type EmploymentStatus = Database['public']['Enums']['employment_status'];

/**
 * Roles provisionable through Employee Management's login-provisioning flow
 * (admin_create_user) — deliberately every non-platform role, since
 * Sebetsa's employee-to-user relationship is 1:1-or-none, not a fixed
 * subset the way Funda360's was.
 */
export const PROVISIONABLE_ROLES = [
  'organization_administrator',
  'operations_manager',
  'regional_manager',
  'site_manager',
  'supervisor',
  'hr_user',
  'employee',
] as const;
export type ProvisionableRole = (typeof PROVISIONABLE_ROLES)[number];

export const PROVISIONABLE_ROLE_LABELS: Record<ProvisionableRole, string> = {
  organization_administrator: 'Organization Administrator',
  operations_manager: 'Operations Manager',
  regional_manager: 'Regional Manager',
  site_manager: 'Site Manager',
  supervisor: 'Supervisor',
  hr_user: 'HR User',
  employee: 'Employee',
};

export interface ProvisionLoginResult {
  userId: string;
  temporaryPassword: string;
}

export interface Department {
  id: string;
  tenantId: string;
  name: string;
  createdAt: string;
  updatedAt: string;
}

export interface CreateDepartmentInput {
  name: string;
}

export type UpdateDepartmentInput = Partial<CreateDepartmentInput>;

export interface Employee {
  id: string;
  tenantId: string;
  profileId: string | null;
  employeeNumber: string;
  firstName: string;
  lastName: string;
  email: string | null;
  phone: string | null;
  departmentId: string | null;
  positionId: string | null;
  supervisorId: string | null;
  regionId: string | null;
  homeSiteId: string | null;
  employmentType: EmploymentType;
  employmentStatus: EmploymentStatus;
  employmentStartDate: string;
  employmentEndDate: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateEmployeeInput {
  employeeNumber: string;
  firstName: string;
  lastName: string;
  email?: string | null;
  phone?: string | null;
  departmentId?: string | null;
  positionId?: string | null;
  supervisorId?: string | null;
  homeSiteId?: string | null;
  employmentType?: EmploymentType;
  employmentStartDate: string;
}

export type UpdateEmployeeInput = Partial<CreateEmployeeInput>;

export interface EmployeesListFilters {
  search?: string;
  employmentStatus?: EmploymentStatus;
  departmentId?: string;
}

export interface EmployeesListPage {
  employees: Employee[];
  totalCount: number;
  page: number;
  pageSize: number;
}
