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

export type ContractVersionRow = TableRow<'contract_versions'>;

export type SiteAreaRow = TableRow<'site_areas'>;
export type SiteAreaInsert = TableInsert<'site_areas'>;
export type SiteAreaUpdate = TableUpdate<'site_areas'>;

export type ScopeOfWorkItemRow = TableRow<'scope_of_work_items'>;
export type ScopeOfWorkItemInsert = TableInsert<'scope_of_work_items'>;
export type ScopeOfWorkItemUpdate = TableUpdate<'scope_of_work_items'>;

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

export type ClientContactRow = TableRow<'client_contacts'>;
export type ClientContactInsert = TableInsert<'client_contacts'>;

export type ContractDocumentRow = TableRow<'contract_documents'>;

export type SlaDefinitionRow = TableRow<'sla_definitions'>;
export type SlaMetricTypeEnum = Database['public']['Enums']['sla_metric_type'];

export type SlaMeasurementRow = TableRow<'sla_measurements'>;

export type SkillRow = TableRow<'skills'>;
export type SkillInsert = TableInsert<'skills'>;

export type EmployeeSkillRow = TableRow<'employee_skills'>;
export type ProficiencyLevelEnum = Database['public']['Enums']['proficiency_level'];

export type EmployeeQualificationRow = TableRow<'employee_qualifications'>;
export type CredentialTypeEnum = Database['public']['Enums']['credential_type'];
export type CredentialStatusEnum = Database['public']['Enums']['credential_status'];

export type TrainingProgramRow = TableRow<'training_programs'>;
export type TrainingEnrollmentRow = TableRow<'training_enrollments'>;
export type TrainingEnrollmentStatusEnum = Database['public']['Enums']['training_enrollment_status'];

export type PerformanceReviewRow = TableRow<'performance_reviews'>;
export type PerformanceReviewStatusEnum = Database['public']['Enums']['performance_review_status'];

export type DevelopmentActionRow = TableRow<'development_actions'>;

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

export type GpsVerificationStatusEnum = Database['public']['Enums']['gps_verification_status'];
export type AttendanceLocationExceptionRow = TableRow<'attendance_location_exceptions'>;

export type PatrolRunStatusEnum = Database['public']['Enums']['patrol_run_status'];
export type CheckpointScanTypeEnum = Database['public']['Enums']['checkpoint_scan_type'];
export type CheckpointScanResultEnum = Database['public']['Enums']['checkpoint_scan_result'];
export type PatrolRouteRow = TableRow<'patrol_routes'>;
export type PatrolRunRow = TableRow<'patrol_runs'>;
export type PatrolCheckpointScanRow = TableRow<'patrol_checkpoint_scans'>;

export type AlertSeverityEnum = Database['public']['Enums']['alert_severity'];
export type AlertStatusEnum = Database['public']['Enums']['alert_status'];
export type OperationalAlertTypeEnum = Database['public']['Enums']['operational_alert_type'];
export type OperationalAlertRow = TableRow<'operational_alerts'>;

export type EmergencyTypeEnum = Database['public']['Enums']['emergency_type'];
export type EmergencyStatusEnum = Database['public']['Enums']['emergency_status'];
export type EmergencyEventRow = TableRow<'emergency_events'>;
export type EmergencyResponseRow = TableRow<'emergency_responses'>;

export type InsightKindEnum = Database['public']['Enums']['insight_kind'];
export type AiQueryLogRow = TableRow<'ai_query_log'>;

export type ShiftRecommendationStatusEnum = Database['public']['Enums']['shift_recommendation_status'];
export type ShiftRecommendationRow = TableRow<'shift_recommendations'>;
