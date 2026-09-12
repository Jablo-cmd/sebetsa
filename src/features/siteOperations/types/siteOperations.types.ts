export interface SiteWorkforceOverview {
  siteId: string;
  assignedCount: number;
  scheduledTodayCount: number;
  presentCount: number;
  lateCount: number;
  absentCount: number;
  openTasksCount: number;
  requiredCount: number | null;
}

export interface StaffingRequirement {
  id: string;
  tenantId: string;
  siteId: string;
  label: string;
  requiredCount: number;
}
