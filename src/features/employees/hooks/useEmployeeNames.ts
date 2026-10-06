import { useEffect, useMemo, useState } from 'react';
import { employeeService } from '@/features/employees/services/employeeService';

/**
 * Resolves display names for a set of employee ids in one request (not one
 * per row), for lists of other entities that only carry an employee id.
 * Returns an id → "First Last" map; ids that cannot be resolved (not visible
 * to the caller) are simply absent, never shown as someone else.
 */
export function useEmployeeNames(ids: string[]): Record<string, string> {
  const key = useMemo(() => [...new Set(ids)].sort().join(','), [ids]);
  const [names, setNames] = useState<Record<string, string>>({});

  useEffect(() => {
    const unique = key ? key.split(',') : [];
    if (unique.length === 0) {
      setNames({});
      return;
    }
    let isCurrent = true;
    employeeService
      .getEmployeeCandidatesByIds(unique)
      .then((rows) => {
        if (isCurrent) setNames(Object.fromEntries(rows.map((row) => [row.id, `${row.firstName} ${row.lastName}`])));
      })
      .catch(() => {
        if (isCurrent) setNames({});
      });
    return () => {
      isCurrent = false;
    };
  }, [key]);

  return names;
}
