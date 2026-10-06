import { useCallback, useEffect, useState } from 'react';
import { employeeService } from '@/features/employees/services/employeeService';
import type { Employee, EmployeesListFilters } from '@/features/employees/types/employee.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PAGE_SIZE = 20;

export interface UseEmployeesListResult {
  employees: Employee[];
  totalCount: number;
  page: number;
  pageSize: number;
  isLoading: boolean;
  error: string | null;
  filters: EmployeesListFilters;
  setFilters: (filters: EmployeesListFilters) => void;
  setPage: (page: number) => void;
  refetch: () => Promise<void>;
}

export function useEmployeesList(tenantId: string | undefined): UseEmployeesListResult {
  const [filters, setFiltersState] = useState<EmployeesListFilters>({});
  const [page, setPage] = useState(1);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      const result = await employeeService.getEmployees(tenantId, filters, page, PAGE_SIZE);
      setEmployees(result.employees);
      setTotalCount(result.totalCount);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load employees.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId, filters, page]);

  useEffect(() => {
    void load();
  }, [load]);

  const setFilters = useCallback((next: EmployeesListFilters) => {
    setFiltersState(next);
    setPage(1);
  }, []);

  return {
    employees,
    totalCount,
    page,
    pageSize: PAGE_SIZE,
    isLoading,
    error,
    filters,
    setFilters,
    setPage,
    refetch: load,
  };
}
