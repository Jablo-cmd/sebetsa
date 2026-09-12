import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useTasks } from '@/features/tasks/hooks/useTasks';
import { TaskDetailModal } from '@/features/tasks/components/TaskDetailModal';
import { taskService } from '@/features/tasks/services/taskService';
import type { Task } from '@/features/tasks/types/task.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_LABEL: Record<string, string> = {
  open: 'Open',
  in_progress: 'In progress',
  completed: 'Completed',
  verified: 'Verified',
  cancelled: 'Cancelled',
  escalated: 'Escalated',
};

/** Operational-management tier: all tenant tasks, generate recurring
 * instances, escalate overdue tasks, verify completed work. */
export function TaskManagementPage() {
  const organization = useCurrentOrganization();
  const { tasks, isLoading, error, refetch } = useTasks(organization?.id);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isRunning, setIsRunning] = useState<'generate' | 'escalate' | null>(null);

  if (!organization) return <NoActiveOrganizationNotice resource="tasks" />;

  const handleGenerate = async () => {
    setIsRunning('generate');
    setActionError(null);
    try {
      await taskService.generateRecurringTasks(organization.id);
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to generate recurring tasks.'));
    } finally {
      setIsRunning(null);
    }
  };

  const handleEscalate = async () => {
    setIsRunning('escalate');
    setActionError(null);
    try {
      await taskService.escalateOverdueTasks(organization.id);
      void refetch();
    } catch (err) {
      setActionError(getDbErrorMessage(err, 'Failed to escalate overdue tasks.'));
    } finally {
      setIsRunning(null);
    }
  };

  return (
    <PageContainer>
      <PageHeader
        title="Task Management"
        description="All operational tasks across your sites."
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => void handleGenerate()} isLoading={isRunning === 'generate'}>
              Generate recurring tasks
            </Button>
            <Button variant="secondary" onClick={() => void handleEscalate()} isLoading={isRunning === 'escalate'}>
              Escalate overdue
            </Button>
          </div>
        }
      />

      <ErrorAlert message={error ?? actionError} />

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : tasks.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No tasks yet.</p>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-border text-xs uppercase text-content-secondary">
                <th className="px-3 py-2">Title</th>
                <th className="px-3 py-2">Priority</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Due</th>
                <th className="px-3 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {tasks.map((task) => (
                <tr key={task.id} className="border-b border-border last:border-0">
                  <td className="px-3 py-2.5">{task.title}</td>
                  <td className="px-3 py-2.5 capitalize">{task.priority}</td>
                  <td className="px-3 py-2.5">{STATUS_LABEL[task.status] ?? task.status}</td>
                  <td className="px-3 py-2.5">{task.dueAt ? new Date(task.dueAt).toLocaleDateString() : '—'}</td>
                  <td className="px-3 py-2.5 text-right">
                    <Button variant="ghost" onClick={() => setSelectedTask(task)}>
                      Review
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <TaskDetailModal
        isOpen={selectedTask !== null}
        onClose={() => setSelectedTask(null)}
        task={selectedTask}
        tenantId={organization.id}
        canAct
        canManage
        onChanged={() => void refetch()}
      />
    </PageContainer>
  );
}
