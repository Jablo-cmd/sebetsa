import { supabase } from '@/lib/supabase';
import type { TaskRow, TaskChecklistItemRow, TaskEvidenceRow, TaskTemplateRow } from '@/lib/dbTypes';
import type { Task, TaskChecklistItem, TaskEvidence, TaskTemplate } from '@/features/tasks/types/task.types';

function toTask(row: TaskRow): Task {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    assigneeId: row.assignee_id,
    teamId: row.team_id,
    supervisorId: row.supervisor_id,
    title: row.title,
    description: row.description,
    priority: row.priority,
    status: row.status,
    dueAt: row.due_at,
    completedAt: row.completed_at,
    completedBy: row.completed_by,
    requiresEvidence: row.requires_evidence,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function toChecklistItem(row: TaskChecklistItemRow): TaskChecklistItem {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    taskId: row.task_id,
    label: row.label,
    sortOrder: row.sort_order,
    isCompleted: row.is_completed,
    completedBy: row.completed_by,
    completedAt: row.completed_at,
    notes: row.notes,
  };
}

function toEvidence(row: TaskEvidenceRow): TaskEvidence {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    taskId: row.task_id,
    kind: row.kind,
    note: row.note,
    submittedBy: row.submitted_by,
    createdAt: row.created_at,
  };
}

function toTemplate(row: TaskTemplateRow): TaskTemplate {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    siteId: row.site_id,
    title: row.title,
    description: row.description,
    instructions: row.instructions,
    priority: row.priority,
    expectedDurationMinutes: row.expected_duration_minutes,
    requiresEvidence: row.requires_evidence,
    defaultAssigneeId: row.default_assignee_id,
    defaultTeamId: row.default_team_id,
    recurrenceFrequency: row.recurrence_frequency as TaskTemplate['recurrenceFrequency'],
    status: row.status,
  };
}

async function getTasks(tenantId: string, filters: { assigneeId?: string; status?: string[] } = {}): Promise<Task[]> {
  let query = supabase.from('tasks').select('*').eq('tenant_id', tenantId);
  if (filters.assigneeId) query = query.eq('assignee_id', filters.assigneeId);
  if (filters.status?.length) query = query.in('status', filters.status);
  const { data, error } = await query.order('due_at', { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data.map(toTask);
}

async function getChecklistItems(taskId: string): Promise<TaskChecklistItem[]> {
  const { data, error } = await supabase.from('task_checklist_items').select('*').eq('task_id', taskId).order('sort_order', { ascending: true });
  if (error) throw error;
  return data.map(toChecklistItem);
}

async function toggleChecklistItem(itemId: string, isCompleted: boolean): Promise<TaskChecklistItem> {
  const { data, error } = await supabase.from('task_checklist_items').update({ is_completed: isCompleted }).eq('id', itemId).select('*').single();
  if (error) throw error;
  return toChecklistItem(data);
}

async function getEvidence(taskId: string): Promise<TaskEvidence[]> {
  const { data, error } = await supabase.from('task_evidence').select('*').eq('task_id', taskId).order('created_at', { ascending: false });
  if (error) throw error;
  return data.map(toEvidence);
}

async function addEvidenceNote(tenantId: string, taskId: string, note: string): Promise<TaskEvidence> {
  const { data, error } = await supabase.from('task_evidence').insert({ tenant_id: tenantId, task_id: taskId, kind: 'note', note }).select('*').single();
  if (error) throw error;
  return toEvidence(data);
}

async function completeTask(taskId: string): Promise<Task> {
  const { data, error } = await supabase.rpc('complete_task', { p_task_id: taskId });
  if (error) throw error;
  return toTask(data);
}

async function verifyTask(taskId: string): Promise<Task> {
  const { data, error } = await supabase.rpc('verify_task', { p_task_id: taskId });
  if (error) throw error;
  return toTask(data);
}

async function reassignTask(taskId: string, newAssigneeId: string, reason?: string): Promise<Task> {
  const { data, error } = await supabase.rpc('reassign_task', { p_task_id: taskId, p_new_assignee_id: newAssigneeId, p_reason: reason });
  if (error) throw error;
  return toTask(data);
}

async function generateRecurringTasks(tenantId: string): Promise<Task[]> {
  const { data, error } = await supabase.rpc('generate_recurring_tasks', { p_tenant_id: tenantId });
  if (error) throw error;
  return (data ?? []).map(toTask);
}

async function escalateOverdueTasks(tenantId: string): Promise<Task[]> {
  const { data, error } = await supabase.rpc('escalate_overdue_tasks', { p_tenant_id: tenantId });
  if (error) throw error;
  return (data ?? []).map(toTask);
}

async function getTemplates(tenantId: string): Promise<TaskTemplate[]> {
  const { data, error } = await supabase.from('task_templates').select('*').eq('tenant_id', tenantId).order('title', { ascending: true });
  if (error) throw error;
  return data.map(toTemplate);
}

async function createTemplate(
  tenantId: string,
  input: { siteId: string; title: string; description?: string; instructions?: string; recurrenceFrequency?: 'daily' | 'weekly' | 'monthly'; requiresEvidence: boolean },
): Promise<TaskTemplate> {
  const { data, error } = await supabase
    .from('task_templates')
    .insert({
      tenant_id: tenantId,
      site_id: input.siteId,
      title: input.title,
      description: input.description ?? null,
      instructions: input.instructions ?? null,
      recurrence_frequency: input.recurrenceFrequency ?? null,
      requires_evidence: input.requiresEvidence,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toTemplate(data);
}

export const taskService = {
  getTasks,
  getChecklistItems,
  toggleChecklistItem,
  getEvidence,
  addEvidenceNote,
  completeTask,
  verifyTask,
  reassignTask,
  generateRecurringTasks,
  escalateOverdueTasks,
  getTemplates,
  createTemplate,
};
