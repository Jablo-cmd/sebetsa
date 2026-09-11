export interface SiteAssignment {
  id: string;
  tenantId: string;
  siteId: string;
  employeeId: string;
  roleOnSite: string | null;
  startDate: string;
  endDate: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateSiteAssignmentInput {
  siteId: string;
  employeeId: string;
  roleOnSite?: string | null;
  startDate: string;
  endDate?: string | null;
}

export interface UpdateSiteAssignmentInput {
  siteId?: string;
  employeeId?: string;
  roleOnSite?: string | null;
  startDate?: string;
  endDate?: string | null;
}

export interface SiteAssignmentsListFilters {
  siteId?: string;
  employeeId?: string;
  /** "current" = no end date or end date in the future; "historical" = end date in the past; omitted = all. */
  when?: 'current' | 'historical';
}
