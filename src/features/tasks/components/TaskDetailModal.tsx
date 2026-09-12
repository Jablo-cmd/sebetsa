import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { taskService } from '@/features/tasks/services/taskService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { retryOnNetworkError } from '@/lib/retry';
import type { Task, TaskChecklistItem, TaskEvidence } from '@/features/tasks/types/task.types';

export interface TaskDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  task: Task | null;
  tenantId: string;
  /** True when the caller is the task's own assignee (or a manager) — controls whether checklist/evidence/complete actions render. */
  canAct: boolean;
  canManage: boolean;
  onChanged: () => void;
}

export function TaskDetailModal({ isOpen, onClose, task, tenantId, canAct, canManage, onChanged }: TaskDetailModalProps) {
  const [checklist, setChecklist] = useState<TaskChecklistItem[]>([]);
  const [evidence, setEvidence] = useState<TaskEvidence[]>([]);
  const [newNote, setNewNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!isOpen || !task) return;
    setError(null);
    void taskService.getChecklistItems(task.id).then(setChecklist);
    void taskService.getEvidence(task.id).then(setEvidence);
  }, [isOpen, task]);

  if (!task) return null;

  const toggleItem = async (item: TaskChecklistItem) => {
    try {
      const updated = await taskService.toggleChecklistItem(item.id, !item.isCompleted);
      setChecklist((prev) => prev.map((i) => (i.id === updated.id ? updated : i)));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to update the checklist item.'));
    }
  };

  const addNote = async () => {
    if (!newNote.trim()) return;
    setIsSubmitting(true);
    setError(null);
    try {
      const created = await taskService.addEvidenceNote(tenantId, task.id, newNote.trim());
      setEvidence((prev) => [created, ...prev]);
      setNewNote('');
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to add the evidence note.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleComplete = async () => {
    setIsSubmitting(true);
    setError(null);
    try {
      await retryOnNetworkError(() => taskService.completeTask(task.id));
      onChanged();
      onClose();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to complete the task.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleVerify = async () => {
    setIsSubmitting(true);
    setError(null);
    try {
      await taskService.verifyTask(task.id);
      onChanged();
      onClose();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to verify the task.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const canComplete = canAct && ['open', 'in_progress', 'escalated'].includes(task.status);
  const canVerify = canManage && task.status === 'completed';

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={task.title}>
      <div className="flex flex-col gap-4">
        {error && <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">{error}</div>}

        {task.description && <p className="text-sm text-content-secondary">{task.description}</p>}

        {checklist.length > 0 && (
          <div>
            <p className="text-sm font-medium text-content-primary">Checklist</p>
            <div className="mt-2 flex flex-col gap-1.5">
              {checklist.map((item) => (
                <label key={item.id} className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={item.isCompleted}
                    disabled={!canAct}
                    onChange={() => void toggleItem(item)}
                    className="focus-ring h-4 w-4 rounded border-border-strong"
                  />
                  <span className={item.isCompleted ? 'text-content-tertiary line-through' : 'text-content-primary'}>{item.label}</span>
                </label>
              ))}
            </div>
          </div>
        )}

        <div>
          <p className="text-sm font-medium text-content-primary">Evidence {task.requiresEvidence && <span className="text-danger-600">(required)</span>}</p>
          <div className="mt-2 flex flex-col gap-2">
            {evidence.map((item) => (
              <p key={item.id} className="rounded-lg border border-border bg-surface-sunken px-3 py-2 text-xs text-content-secondary">
                {item.note}
              </p>
            ))}
            {canAct && (
              <div className="flex gap-2">
                <TextField label="Add a note" placeholder="Describe what was done" value={newNote} onChange={(event) => setNewNote(event.target.value)} />
              </div>
            )}
            {canAct && (
              <Button variant="secondary" onClick={() => void addNote()} isLoading={isSubmitting} disabled={!newNote.trim()}>
                Add evidence
              </Button>
            )}
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          {canComplete && (
            <Button onClick={() => void handleComplete()} isLoading={isSubmitting}>
              Mark complete
            </Button>
          )}
          {canVerify && (
            <Button onClick={() => void handleVerify()} isLoading={isSubmitting}>
              Verify
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
}
