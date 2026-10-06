import { useEffect, useState } from 'react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useSitesList } from '@/features/attendance/hooks/useSitesList';
import { employeeService, type EmployeeCandidate } from '@/features/employees/services/employeeService';
import { taskService } from '@/features/tasks/services/taskService';
import type { Task } from '@/features/tasks/types/task.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const PRIORITIES: Task['priority'][] = ['low', 'normal', 'high', 'urgent'];

export interface NewTaskModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  onCreated: () => void;
}

/** Creates an ad-hoc task (with an optional checklist) for a site, optionally assigned to an employee. */
export function NewTaskModal({ isOpen, onClose, tenantId, onCreated }: NewTaskModalProps) {
  const { sites } = useSitesList(tenantId);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [siteId, setSiteId] = useState('');
  const [priority, setPriority] = useState<Task['priority']>('normal');
  const [dueDate, setDueDate] = useState('');
  const [requiresEvidence, setRequiresEvidence] = useState(false);
  const [checklistText, setChecklistText] = useState('');
  const [assigneeSearch, setAssigneeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [assignee, setAssignee] = useState<EmployeeCandidate | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [touched, setTouched] = useState(false);

  useEffect(() => {
    if (!isOpen) return;
    setTitle('');
    setDescription('');
    setSiteId('');
    setPriority('normal');
    setDueDate('');
    setRequiresEvidence(false);
    setChecklistText('');
    setAssigneeSearch('');
    setCandidates([]);
    setAssignee(null);
    setError(null);
    setTouched(false);
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen || !assigneeSearch.trim()) {
      setCandidates([]);
      return;
    }
    let cancelled = false;
    employeeService
      .searchEmployeeCandidates(tenantId, assigneeSearch)
      .then((results) => {
        if (!cancelled) setCandidates(results);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(getDbErrorMessage(err, 'Failed to search employees.'));
      });
    return () => {
      cancelled = true;
    };
  }, [isOpen, tenantId, assigneeSearch]);

  const titleError = touched && !title.trim() ? 'Title is required' : undefined;
  const siteError = touched && !siteId ? 'Site is required' : undefined;

  const handleSave = async () => {
    setTouched(true);
    if (!title.trim() || !siteId) return;
    setIsSaving(true);
    setError(null);
    try {
      await taskService.createTask({
        siteId,
        title: title.trim(),
        description: description.trim() || undefined,
        priority,
        // A date-only due date means "by the end of that day" (UTC).
        dueAt: dueDate ? `${dueDate}T23:59:00.000Z` : undefined,
        assigneeId: assignee?.id,
        requiresEvidence,
        checklist: checklistText.split('\n').map((line) => line.trim()).filter(Boolean),
      });
      onCreated();
      onClose();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the task.'));
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="New task"
      footer={
        <Button onClick={() => void handleSave()} isLoading={isSaving}>
          Create task
        </Button>
      }
    >
      <div className="flex flex-col gap-4">
        {error && (
          <div role="alert" className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600">
            {error}
          </div>
        )}
        <TextField label="Title" required value={title} onChange={(event) => setTitle(event.target.value)} error={titleError} />
        <TextField label="Description" value={description} onChange={(event) => setDescription(event.target.value)} />

        <div>
          <label htmlFor="new-task-site" className="mb-1.5 block text-sm font-medium text-content-primary">
            Site <span className="text-danger-600">*</span>
          </label>
          <select
            id="new-task-site"
            value={siteId}
            onChange={(event) => setSiteId(event.target.value)}
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
          >
            <option value="">Select a site…</option>
            {sites.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
          {siteError && (
            <p role="alert" className="mt-1.5 text-xs font-medium text-danger-600">
              {siteError}
            </p>
          )}
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="new-task-priority" className="mb-1.5 block text-sm font-medium text-content-primary">
              Priority
            </label>
            <select
              id="new-task-priority"
              value={priority}
              onChange={(event) => setPriority(event.target.value as Task['priority'])}
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm capitalize text-content-primary"
            >
              {PRIORITIES.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </div>
          <TextField label="Due date" type="date" value={dueDate} onChange={(event) => setDueDate(event.target.value)} />
        </div>

        <div>
          <TextField
            label="Assign to (optional)"
            hint={assignee ? `Selected: ${assignee.firstName} ${assignee.lastName}` : 'Search by name…'}
            placeholder="Search by name…"
            value={assigneeSearch}
            onChange={(event) => setAssigneeSearch(event.target.value)}
          />
          {candidates.length > 0 && (
            <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
              {candidates.map((candidate) => (
                <button
                  key={candidate.id}
                  type="button"
                  onClick={() => {
                    setAssignee(candidate);
                    setAssigneeSearch('');
                  }}
                  className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3 py-2 text-left text-sm hover:bg-surface-sunken"
                >
                  {candidate.firstName} {candidate.lastName}
                </button>
              ))}
            </div>
          )}
        </div>

        <label className="flex flex-col gap-1.5 text-sm font-medium text-content-primary">
          Checklist (one item per line)
          <textarea
            rows={4}
            value={checklistText}
            onChange={(event) => setChecklistText(event.target.value)}
            className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-sm font-normal text-content-primary"
          />
        </label>

        <label className="flex items-center gap-2 text-sm font-medium text-content-primary">
          <input
            type="checkbox"
            checked={requiresEvidence}
            onChange={(event) => setRequiresEvidence(event.target.checked)}
            className="focus-ring h-4 w-4 rounded border-border-strong"
          />
          Evidence is required to complete this task
        </label>
      </div>
    </Modal>
  );
}
