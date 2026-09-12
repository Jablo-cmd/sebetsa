export type TaskStatus = 'open' | 'in_progress' | 'completed' | 'cancelled' | 'escalated' | 'verified';
export type TaskPriority = 'low' | 'normal' | 'high' | 'urgent';

export interface Task {
  id: string;
  tenantId: string;
  siteId: string;
  assigneeId: string | null;
  teamId: string | null;
  supervisorId: string | null;
  title: string;
  description: string | null;
  priority: TaskPriority;
  status: TaskStatus;
  dueAt: string | null;
  completedAt: string | null;
  completedBy: string | null;
  requiresEvidence: boolean;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface TaskChecklistItem {
  id: string;
  tenantId: string;
  taskId: string;
  label: string;
  sortOrder: number;
  isCompleted: boolean;
  completedBy: string | null;
  completedAt: string | null;
  notes: string | null;
}

export interface TaskEvidence {
  id: string;
  tenantId: string;
  taskId: string;
  kind: 'note' | 'confirmation';
  note: string | null;
  submittedBy: string | null;
  createdAt: string;
}

export interface TaskTemplate {
  id: string;
  tenantId: string;
  siteId: string;
  title: string;
  description: string | null;
  instructions: string | null;
  priority: TaskPriority;
  expectedDurationMinutes: number | null;
  requiresEvidence: boolean;
  defaultAssigneeId: string | null;
  defaultTeamId: string | null;
  recurrenceFrequency: 'daily' | 'weekly' | 'monthly' | null;
  status: 'active' | 'inactive' | 'onboarding' | 'offboarded';
}
