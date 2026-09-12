import { useCallback, useEffect, useState } from 'react';
import { taskService } from '@/features/tasks/services/taskService';
import type { Task } from '@/features/tasks/types/task.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseTasksResult {
  tasks: Task[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useTasks(tenantId: string | undefined, filters: { assigneeId?: string; status?: string[] } = {}): UseTasksResult {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const { assigneeId, status } = filters;

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setTasks(await taskService.getTasks(tenantId, { assigneeId, status }));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load tasks.'));
    } finally {
      setIsLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tenantId, assigneeId, status?.join(',')]);

  useEffect(() => {
    void load();
  }, [load]);

  return { tasks, isLoading, error, refetch: load };
}
