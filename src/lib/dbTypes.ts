import type { Database } from '@/lib/database.types';

/**
 * Convenience Row/Insert/Update aliases over the generated `Database` type,
 * one per Sebetsa table — service files import from here instead of
 * reaching into `Database['public']['Tables'][...]` directly.
 */
type Tables = Database['public']['Tables'];
type TableRow<T extends keyof Tables> = Tables[T]['Row'];
type TableInsert<T extends keyof Tables> = Tables[T]['Insert'];
type TableUpdate<T extends keyof Tables> = Tables[T]['Update'];

export type OrganizationRow = TableRow<'organizations'>;
export type OrganizationInsert = TableInsert<'organizations'>;
export type OrganizationUpdate = TableUpdate<'organizations'>;

export type ProfileRow = TableRow<'profiles'>;
export type ProfileInsert = TableInsert<'profiles'>;
export type ProfileUpdate = TableUpdate<'profiles'>;

export type RegionRow = TableRow<'regions'>;
export type RegionInsert = TableInsert<'regions'>;
export type RegionUpdate = TableUpdate<'regions'>;

export type ClientRow = TableRow<'clients'>;
export type ClientInsert = TableInsert<'clients'>;
export type ClientUpdate = TableUpdate<'clients'>;

export type SiteRow = TableRow<'sites'>;
export type SiteInsert = TableInsert<'sites'>;
export type SiteUpdate = TableUpdate<'sites'>;

export type ContractRow = TableRow<'contracts'>;
export type ContractInsert = TableInsert<'contracts'>;
export type ContractUpdate = TableUpdate<'contracts'>;

export type ContractSiteRow = TableRow<'contract_sites'>;

export type DepartmentRow = TableRow<'departments'>;
export type DepartmentInsert = TableInsert<'departments'>;
export type DepartmentUpdate = TableUpdate<'departments'>;

export type PositionRow = TableRow<'positions'>;
export type PositionInsert = TableInsert<'positions'>;
export type PositionUpdate = TableUpdate<'positions'>;

export type EmployeeRow = TableRow<'employees'>;
export type EmployeeInsert = TableInsert<'employees'>;
export type EmployeeUpdate = TableUpdate<'employees'>;

export type TeamRow = TableRow<'teams'>;
export type TeamInsert = TableInsert<'teams'>;
export type TeamUpdate = TableUpdate<'teams'>;

export type TeamMemberRow = TableRow<'team_members'>;
export type TeamMemberInsert = TableInsert<'team_members'>;

export type SiteAssignmentRow = TableRow<'site_assignments'>;
export type SiteAssignmentInsert = TableInsert<'site_assignments'>;
export type SiteAssignmentUpdate = TableUpdate<'site_assignments'>;

export type ShiftDefinitionRow = TableRow<'shift_definitions'>;
export type ShiftDefinitionInsert = TableInsert<'shift_definitions'>;
export type ShiftDefinitionUpdate = TableUpdate<'shift_definitions'>;

export type ShiftRow = TableRow<'shifts'>;
export type ShiftInsert = TableInsert<'shifts'>;
export type ShiftUpdate = TableUpdate<'shifts'>;

export type ShiftSubstitutionRow = TableRow<'shift_substitutions'>;
export type ShiftSubstitutionInsert = TableInsert<'shift_substitutions'>;

export type AttendanceRecordRow = TableRow<'attendance_records'>;
export type AttendanceRecordInsert = TableInsert<'attendance_records'>;
export type AttendanceRecordUpdate = TableUpdate<'attendance_records'>;
export type LeaveRequestRow = TableRow<'leave_requests'>;
export type LeaveRequestInsert = TableInsert<'leave_requests'>;
export type LeaveRequestUpdate = TableUpdate<'leave_requests'>;

export type EmployeeAvailabilityRow = TableRow<'employee_availability'>;
export type EmployeeAvailabilityInsert = TableInsert<'employee_availability'>;
export type EmployeeAvailabilityUpdate = TableUpdate<'employee_availability'>;

export type EmployeeAvailabilityExceptionRow = TableRow<'employee_availability_exceptions'>;
export type EmployeeAvailabilityExceptionInsert = TableInsert<'employee_availability_exceptions'>;

export type TaskRow = TableRow<'tasks'>;
export type TaskInsert = TableInsert<'tasks'>;
export type TaskUpdate = TableUpdate<'tasks'>;
export type TaskCommentRow = TableRow<'task_comments'>;
export type TaskStatusEnum = Database['public']['Enums']['task_status'];
export type TaskPriorityEnum = Database['public']['Enums']['task_priority'];

export type TaskChecklistItemRow = TableRow<'task_checklist_items'>;
export type TaskChecklistItemInsert = TableInsert<'task_checklist_items'>;

export type TaskEvidenceRow = TableRow<'task_evidence'>;
export type TaskEvidenceInsert = TableInsert<'task_evidence'>;

export type TaskTemplateRow = TableRow<'task_templates'>;
export type TaskTemplateInsert = TableInsert<'task_templates'>;
export type TaskTemplateUpdate = TableUpdate<'task_templates'>;

export type LeaveTypeRow = TableRow<'leave_types'>;
export type LeaveTypeInsert = TableInsert<'leave_types'>;
export type LeaveTypeUpdate = TableUpdate<'leave_types'>;

export type ComplianceRequirementRow = TableRow<'compliance_requirements'>;
export type ComplianceRequirementInsert = TableInsert<'compliance_requirements'>;

export type ComplianceRecordRow = TableRow<'compliance_records'>;
export type ComplianceStatusEnum = Database['public']['Enums']['compliance_status'];

export type IncidentRow = TableRow<'incidents'>;
export type IncidentCategoryEnum = Database['public']['Enums']['incident_category'];
export type IncidentSeverityEnum = Database['public']['Enums']['incident_severity'];
export type IncidentStatusEnum = Database['public']['Enums']['incident_status'];

export type IncidentAffectedEmployeeRow = TableRow<'incident_affected_employees'>;

export type IncidentActionRow = TableRow<'incident_actions'>;
export type IncidentActionStatusEnum = Database['public']['Enums']['incident_action_status'];

export type AssetRow = TableRow<'assets'>;
export type AssetStatusEnum = Database['public']['Enums']['asset_status'];

export type AssetAssignmentRow = TableRow<'asset_assignments'>;
export type AssetMaintenanceRecordRow = TableRow<'asset_maintenance_records'>;

export type InventoryItemRow = TableRow<'inventory_items'>;
export type InventoryItemInsert = TableInsert<'inventory_items'>;

export type InventoryMovementRow = TableRow<'inventory_movements'>;
export type InventoryMovementTypeEnum = Database['public']['Enums']['inventory_movement_type'];

export type ProcurementRequestRow = TableRow<'procurement_requests'>;
export type ProcurementStatusEnum = Database['public']['Enums']['procurement_status'];

export type LeavePolicyRow = TableRow<'leave_policies'>;
export type LeavePolicyInsert = TableInsert<'leave_policies'>;
export type LeavePolicyUpdate = TableUpdate<'leave_policies'>;

export type LeaveBalanceRow = TableRow<'leave_balances'>;

export type LeaveBalanceTransactionRow = TableRow<'leave_balance_transactions'>;

export type LeaveStatusEnum = Database['public']['Enums']['leave_status'];

export type AttendancePolicyRow = TableRow<'attendance_policies'>;
export type AttendancePolicyInsert = TableInsert<'attendance_policies'>;
export type AttendancePolicyUpdate = TableUpdate<'attendance_policies'>;

export type AttendanceBreakRow = TableRow<'attendance_breaks'>;

export type AttendanceCorrectionRow = TableRow<'attendance_corrections'>;
export type AttendanceCorrectionFieldEnum = Database['public']['Enums']['attendance_correction_field'];
export type AttendanceCorrectionStatusEnum = Database['public']['Enums']['attendance_correction_status'];

export type SiteStaffingRequirementRow = TableRow<'site_staffing_requirements'>;
export type SiteStaffingRequirementInsert = TableInsert<'site_staffing_requirements'>;
export type SiteStaffingRequirementUpdate = TableUpdate<'site_staffing_requirements'>;

export type EmployeeDocumentRow = TableRow<'employee_documents'>;
export type DocumentTypeEnum = Database['public']['Enums']['document_type'];
export type DocumentStatusEnum = Database['public']['Enums']['document_status'];

export type NotificationRow = TableRow<'notifications'>;
export type AuditLogRow = TableRow<'audit_log'>;

export type UserRoleEnum = Database['public']['Enums']['user_role'];
