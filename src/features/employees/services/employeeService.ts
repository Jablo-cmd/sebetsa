import { supabase } from '@/lib/supabase';
import type { EmployeeRow, EmployeeInsert, EmployeeUpdate } from '@/lib/dbTypes';
import type {
  Employee,
  CreateEmployeeInput,
  UpdateEmployeeInput,
  EmployeesListFilters,
  EmployeesListPage,
  ProvisionableRole,
  ProvisionLoginResult,
} from '@/features/employees/types/employee.types';

const DEFAULT_PAGE_SIZE = 20;

export interface EmployeeCandidate {
  id: string;
  firstName: string;
  lastName: string;
}

/**
 * Search-driven candidate lookup for the "reports to" picker — the staff
 * directory is paginated (see getEmployees below), so a plain `<select>`
 * fed by whatever page happens to be loaded would silently omit most of the
 * organization's employees.
 */
async function searchEmployeeCandidates(tenantId: string, search = '', excludeId?: string): Promise<EmployeeCandidate[]> {
  let query = supabase
    .from('employees')
    .select('id, first_name, last_name')
    .eq('tenant_id', tenantId);

  if (excludeId) query = query.neq('id', excludeId);

  const term = search.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.or(`first_name.ilike.%${escaped}%,last_name.ilike.%${escaped}%`);
  }

  const { data, error } = await query.order('first_name', { ascending: true }).limit(20);
  if (error) throw error;
  return data.map((row) => ({ id: row.id, firstName: row.first_name, lastName: row.last_name }));
}

/** Exported so other employee-adjacent services can reuse it instead of re-declaring their own mapper. */
export function toEmployee(row: EmployeeRow): Employee {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    profileId: row.profile_id,
    employeeNumber: row.employee_number,
    firstName: row.first_name,
    lastName: row.last_name,
    email: row.email,
    phone: row.phone,
    departmentId: row.department_id,
    positionId: row.position_id,
    supervisorId: row.supervisor_id,
    regionId: row.region_id,
    homeSiteId: row.home_site_id,
    employmentType: row.employment_type,
    employmentStatus: row.employment_status,
    employmentStartDate: row.employment_start_date,
    employmentEndDate: row.employment_end_date,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getEmployees(
  tenantId: string,
  filters: EmployeesListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<EmployeesListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('employees').select('*', { count: 'exact' }).eq('tenant_id', tenantId);

  const term = filters.search?.trim();
  if (term) {
    const escaped = term.replace(/[%,]/g, '');
    query = query.or(
      `first_name.ilike.%${escaped}%,last_name.ilike.%${escaped}%,employee_number.ilike.%${escaped}%`,
    );
  }
  if (filters.employmentStatus) query = query.eq('employment_status', filters.employmentStatus);
  if (filters.departmentId) query = query.eq('department_id', filters.departmentId);

  const { data, error, count } = await query.order('last_name', { ascending: true }).range(from, to);
  if (error) throw error;

  return {
    employees: data.map(toEmployee),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}

async function getEmployee(id: string): Promise<Employee | null> {
  const { data, error } = await supabase.from('employees').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toEmployee(data) : null;
}

/** Self-service: the employee record linked to the caller's own profile, if any. */
async function getMyEmployee(profileId: string): Promise<Employee | null> {
  const { data, error } = await supabase.from('employees').select('*').eq('profile_id', profileId).maybeSingle();
  if (error) throw error;
  return data ? toEmployee(data) : null;
}

function toInsertPayload(tenantId: string, input: CreateEmployeeInput): EmployeeInsert {
  return {
    tenant_id: tenantId,
    employee_number: input.employeeNumber,
    first_name: input.firstName,
    last_name: input.lastName,
    email: input.email ?? null,
    phone: input.phone ?? null,
    department_id: input.departmentId ?? null,
    position_id: input.positionId ?? null,
    supervisor_id: input.supervisorId ?? null,
    home_site_id: input.homeSiteId ?? null,
    employment_type: input.employmentType ?? undefined,
    employment_start_date: input.employmentStartDate,
  };
}

async function createEmployee(tenantId: string, input: CreateEmployeeInput): Promise<Employee> {
  const { data, error } = await supabase.from('employees').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toEmployee(data);
}

async function updateEmployee(id: string, updates: UpdateEmployeeInput): Promise<Employee> {
  const payload: EmployeeUpdate = {};
  if (updates.employeeNumber !== undefined) payload.employee_number = updates.employeeNumber;
  if (updates.firstName !== undefined) payload.first_name = updates.firstName;
  if (updates.lastName !== undefined) payload.last_name = updates.lastName;
  if (updates.email !== undefined) payload.email = updates.email;
  if (updates.phone !== undefined) payload.phone = updates.phone;
  if (updates.departmentId !== undefined) payload.department_id = updates.departmentId;
  if (updates.positionId !== undefined) payload.position_id = updates.positionId;
  if (updates.supervisorId !== undefined) payload.supervisor_id = updates.supervisorId;
  if (updates.homeSiteId !== undefined) payload.home_site_id = updates.homeSiteId;
  if (updates.employmentType !== undefined) payload.employment_type = updates.employmentType;
  if (updates.employmentStartDate !== undefined) payload.employment_start_date = updates.employmentStartDate;

  const { data, error } = await supabase.from('employees').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toEmployee(data);
}

/**
 * The only path that terminates an employee — calls the SECURITY DEFINER
 * terminate_employee() RPC, which atomically sets employment_status and, if
 * a login is linked, deactivates it in the same transaction.
 */
async function terminate(id: string, terminationDate: string): Promise<Employee> {
  const { data, error } = await supabase.rpc('terminate_employee', {
    p_employee_id: id,
    p_termination_date: terminationDate,
  });
  if (error) throw error;
  return toEmployee(data);
}

async function reactivate(id: string): Promise<Employee> {
  const { data, error } = await supabase.rpc('reactivate_employee', { p_employee_id: id });
  if (error) throw error;
  return toEmployee(data);
}

/**
 * The only path that provisions a login for an existing employee — calls
 * the SECURITY DEFINER provision_employee_login() RPC, which creates the
 * auth user and links employees.profile_id back to it in the same
 * transaction. Rejects (server-side) if the employee already has a linked
 * login, has no email on file, or the role isn't provisionable.
 */
async function provisionLogin(
  employeeId: string,
  role: ProvisionableRole,
  phone: string | null = null,
): Promise<ProvisionLoginResult> {
  const { data, error } = await supabase.rpc('provision_employee_login', {
    p_employee_id: employeeId,
    p_role: role,
    p_phone: phone ?? undefined,
  });
  if (error) throw error;

  const row = data?.[0];
  if (!row) throw new Error('Login provisioning did not return the expected result.');
  return { userId: row.user_id, temporaryPassword: row.temporary_password };
}

export const employeeService = {
  getEmployees,
  getEmployee,
  getMyEmployee,
  searchEmployeeCandidates,
  createEmployee,
  updateEmployee,
  terminate,
  reactivate,
  provisionLogin,
};
