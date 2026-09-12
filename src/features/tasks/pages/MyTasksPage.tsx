import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { OfflineBanner } from '@/components/ui/OfflineBanner';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { useTasks } from '@/features/tasks/hooks/useTasks';
import { TaskDetailModal } from '@/features/tasks/components/TaskDetailModal';
import type { Task } from '@/features/tasks/types/task.types';
import type { TaskStatusEnum } from '@/lib/dbTypes';

const STATUS_LABEL: Record<string, string> = {
  open: 'Open',
  in_progress: 'In progress',
  completed: 'Completed',
  verified: 'Verified',
  cancelled: 'Cancelled',
  escalated: 'Escalated',
};

const STATUS_TONES: Record<TaskStatusEnum, StatusTone> = {
  open: 'neutral',
  in_progress: 'info',
  completed: 'success',
  verified: 'success',
  cancelled: 'neutral',
  escalated: 'danger',
};

/** Employee self-service: tasks assigned to me, due-today/overdue first (sorted by due_at). */
export function MyTasksPage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();
  const { tasks, isLoading, error, refetch } = useTasks(employee?.tenantId, { assigneeId: employee?.id });
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);

  return (
    <PageContainer>
      <PageHeader title="My Tasks" description="Tasks assigned to you, due date first." />

      <OfflineBanner />
      <ErrorAlert message={employeeError ?? error} />

      {employeeLoading || isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : tasks.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">You have no tasks right now.</p>
      ) : (
        <div className="mt-4 flex flex-col gap-2">
          {tasks.map((task) => (
            <button
              key={task.id}
              type="button"
              onClick={() => setSelectedTask(task)}
              className="focus-ring flex items-center justify-between rounded-xl border border-border bg-surface-raised p-4 text-left hover:bg-surface-sunken"
            >
              <div>
                <p className="text-sm font-medium text-content-primary">{task.title}</p>
                {task.dueAt && <p className="text-xs text-content-tertiary">Due {new Date(task.dueAt).toLocaleString()}</p>}
              </div>
              <StatusBadge label={STATUS_LABEL[task.status] ?? task.status} tone={STATUS_TONES[task.status]} />
            </button>
          ))}
        </div>
      )}

      {employee && (
        <TaskDetailModal
          isOpen={selectedTask !== null}
          onClose={() => setSelectedTask(null)}
          task={selectedTask}
          tenantId={employee.tenantId}
          canAct
          canManage={false}
          onChanged={() => void refetch()}
        />
      )}
    </PageContainer>
  );
}
