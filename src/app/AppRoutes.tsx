import { lazy, Suspense, type ComponentType } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { ProtectedRoute } from '@/routes/ProtectedRoute';
import { PublicOnlyRoute } from '@/routes/PublicOnlyRoute';
import { TenantGate } from '@/routes/TenantGate';
import { RequirePermission } from '@/routes/RequirePermission';
import { DashboardLayout } from '@/components/layout/DashboardLayout';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';

/**
 * Route-level code splitting: each page becomes its own chunk, fetched only
 * when its route is visited, instead of one large bundle shipped up front.
 * `named` adapts a module's named export to the default export React.lazy
 * requires, without renaming exports across the codebase.
 */
function named<T extends ComponentType<object>>(
  load: () => Promise<Record<string, T>>,
  exportName: string,
) {
  return lazy(() => load().then((module) => ({ default: module[exportName] as T })));
}

const LoginPage = named(() => import('@/features/auth/pages/LoginPage'), 'LoginPage');
const ForgotPasswordPage = named(
  () => import('@/features/auth/pages/ForgotPasswordPage'),
  'ForgotPasswordPage',
);
const ResetPasswordPage = named(
  () => import('@/features/auth/pages/ResetPasswordPage'),
  'ResetPasswordPage',
);
const ActivateAccountPage = named(
  () => import('@/features/auth/pages/ActivateAccountPage'),
  'ActivateAccountPage',
);
const VerifyEmailPage = named(
  () => import('@/features/auth/pages/VerifyEmailPage'),
  'VerifyEmailPage',
);
const MfaChallengePage = named(
  () => import('@/features/mfa/pages/MfaChallengePage'),
  'MfaChallengePage',
);
const DashboardPage = named(() => import('@/pages/DashboardPage'), 'DashboardPage');
const MyProfilePage = named(() => import('@/pages/MyProfilePage'), 'MyProfilePage');
const OrganizationsPage = named(
  () => import('@/features/tenant/pages/OrganizationsPage'),
  'OrganizationsPage',
);
const UsersPage = named(() => import('@/features/users/pages/UsersPage'), 'UsersPage');
const UserProfilePage = named(
  () => import('@/features/users/pages/UserProfilePage'),
  'UserProfilePage',
);
const EmployeesPage = named(
  () => import('@/features/employees/pages/EmployeesPage'),
  'EmployeesPage',
);
const EmployeeProfilePage = named(
  () => import('@/features/employees/pages/EmployeeProfilePage'),
  'EmployeeProfilePage',
);
const DepartmentsPage = named(
  () => import('@/features/employees/pages/DepartmentsPage'),
  'DepartmentsPage',
);
const PositionsPage = named(
  () => import('@/features/employees/pages/PositionsPage'),
  'PositionsPage',
);
const TeamsPage = named(() => import('@/features/teams/pages/TeamsPage'), 'TeamsPage');
const TeamDetailPage = named(() => import('@/features/teams/pages/TeamDetailPage'), 'TeamDetailPage');
const SiteOperationsPage = named(
  () => import('@/features/siteOperations/pages/SiteOperationsPage'),
  'SiteOperationsPage',
);
const SiteAssignmentsPage = named(
  () => import('@/features/siteAssignments/pages/SiteAssignmentsPage'),
  'SiteAssignmentsPage',
);
const AttendancePage = named(
  () => import('@/features/attendance/pages/AttendancePage'),
  'AttendancePage',
);
const MyAttendancePage = named(
  () => import('@/features/attendance/pages/MyAttendancePage'),
  'MyAttendancePage',
);
const AttendanceCorrectionsPage = named(
  () => import('@/features/attendance/pages/AttendanceCorrectionsPage'),
  'AttendanceCorrectionsPage',
);
const SchedulePage = named(() => import('@/features/scheduling/pages/SchedulePage'), 'SchedulePage');
const MySchedulePage = named(
  () => import('@/features/scheduling/pages/MySchedulePage'),
  'MySchedulePage',
);
const ShiftDefinitionsPage = named(
  () => import('@/features/scheduling/pages/ShiftDefinitionsPage'),
  'ShiftDefinitionsPage',
);
const AvailabilityPage = named(
  () => import('@/features/availability/pages/AvailabilityPage'),
  'AvailabilityPage',
);
const MyLeavePage = named(() => import('@/features/leave/pages/MyLeavePage'), 'MyLeavePage');
const MyTasksPage = named(() => import('@/features/tasks/pages/MyTasksPage'), 'MyTasksPage');
const TaskManagementPage = named(
  () => import('@/features/tasks/pages/TaskManagementPage'),
  'TaskManagementPage',
);
const MyDocumentsPage = named(
  () => import('@/features/documents/pages/MyDocumentsPage'),
  'MyDocumentsPage',
);
const EmployeeDocumentsPage = named(
  () => import('@/features/documents/pages/EmployeeDocumentsPage'),
  'EmployeeDocumentsPage',
);
const IncidentsPage = named(
  () => import('@/features/compliance/pages/IncidentsPage'),
  'IncidentsPage',
);
const CompliancePage = named(
  () => import('@/features/compliance/pages/CompliancePage'),
  'CompliancePage',
);
const AssetsPage = named(() => import('@/features/assets/pages/AssetsPage'), 'AssetsPage');
const InventoryPage = named(() => import('@/features/assets/pages/InventoryPage'), 'InventoryPage');
const ProcurementPage = named(
  () => import('@/features/assets/pages/ProcurementPage'),
  'ProcurementPage',
);
const MyDevelopmentPage = named(
  () => import('@/features/workforceDevelopment/pages/MyDevelopmentPage'),
  'MyDevelopmentPage',
);
const WorkforceDevelopmentPage = named(
  () => import('@/features/workforceDevelopment/pages/WorkforceDevelopmentPage'),
  'WorkforceDevelopmentPage',
);
const ReportsPage = named(() => import('@/features/reports/pages/ReportsPage'), 'ReportsPage');
const TeamLeavePage = named(() => import('@/features/leave/pages/TeamLeavePage'), 'TeamLeavePage');
const LeaveManagementPage = named(
  () => import('@/features/leave/pages/LeaveManagementPage'),
  'LeaveManagementPage',
);
const LeaveConfigurationPage = named(
  () => import('@/features/leave/pages/LeaveConfigurationPage'),
  'LeaveConfigurationPage',
);
const NotificationsPage = named(
  () => import('@/features/notifications/pages/NotificationsPage'),
  'NotificationsPage',
);
const NotificationSettingsPage = named(
  () => import('@/features/notifications/pages/NotificationSettingsPage'),
  'NotificationSettingsPage',
);
const RegionsPage = named(() => import('@/features/orgStructure/pages/RegionsPage'), 'RegionsPage');
const RegionDetailPage = named(
  () => import('@/features/orgStructure/pages/RegionDetailPage'),
  'RegionDetailPage',
);
const ClientsPage = named(() => import('@/features/orgStructure/pages/ClientsPage'), 'ClientsPage');
const ClientDetailPage = named(
  () => import('@/features/orgStructure/pages/ClientDetailPage'),
  'ClientDetailPage',
);
const SitesPage = named(() => import('@/features/orgStructure/pages/SitesPage'), 'SitesPage');
const SiteDetailPage = named(() => import('@/features/orgStructure/pages/SiteDetailPage'), 'SiteDetailPage');
const ContractsPage = named(() => import('@/features/orgStructure/pages/ContractsPage'), 'ContractsPage');
const ContractDetailPage = named(
  () => import('@/features/orgStructure/pages/ContractDetailPage'),
  'ContractDetailPage',
);
const MyPatrolsPage = named(() => import('@/features/patrols/pages/MyPatrolsPage'), 'MyPatrolsPage');
const PatrolOversightPage = named(
  () => import('@/features/patrols/pages/PatrolOversightPage'),
  'PatrolOversightPage',
);
const CommandCentrePage = named(
  () => import('@/features/commandCentre/pages/CommandCentrePage'),
  'CommandCentrePage',
);
const OperationalAlertsPage = named(
  () => import('@/features/commandCentre/pages/OperationalAlertsPage'),
  'OperationalAlertsPage',
);
const EmergencyResponsePage = named(
  () => import('@/features/emergency/pages/EmergencyResponsePage'),
  'EmergencyResponsePage',
);
const AiAssistantPage = named(
  () => import('@/features/intelligence/pages/AiAssistantPage'),
  'AiAssistantPage',
);
const SchedulingRecommendationsPage = named(
  () => import('@/features/intelligence/pages/SchedulingRecommendationsPage'),
  'SchedulingRecommendationsPage',
);

export function AppRoutes() {
  return (
    <Suspense fallback={<FullScreenSpinner />}>
      <Routes>
        <Route element={<PublicOnlyRoute />}>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/forgot-password" element={<ForgotPasswordPage />} />
        </Route>

        <Route path="/reset-password" element={<ResetPasswordPage />} />
        <Route path="/activate-account" element={<ActivateAccountPage />} />
        <Route path="/verify-email" element={<VerifyEmailPage />} />
        <Route path="/mfa-challenge" element={<MfaChallengePage />} />

        <Route element={<ProtectedRoute />}>
          <Route element={<TenantGate />}>
            <Route element={<DashboardLayout />}>
              {/* /dashboard, /my-profile, /notifications are the only routes
                  with no RequirePermission guard — every signed-in,
                  tenant-gated user may reach them. */}
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/my-profile" element={<MyProfilePage />} />
              <Route path="/notifications" element={<NotificationsPage />} />
              <Route path="/notifications/settings" element={<NotificationSettingsPage />} />
              {/* My Schedule: an employee's own upcoming shifts. Same "no
                  guard needed" shape as Dashboard/My Profile — it is
                  inherently self-scoped, not a permission-gated module. */}
              <Route path="/schedule/mine" element={<MySchedulePage />} />

              <Route element={<RequirePermission permission="tenant.switch" />}>
                <Route path="/organizations" element={<OrganizationsPage />} />
              </Route>

              {/* User & role administration — gated on profile.manage_any,
                  matching both the sidebar (see NAV_MODEL) and the page's
                  own canManageUsers() check. */}
              <Route element={<RequirePermission permission="profile.manage_any" />}>
                <Route path="/users" element={<UsersPage />} />
                <Route path="/users/:id" element={<UserProfilePage />} />
              </Route>

              <Route element={<RequirePermission permission="employee.view" />}>
                <Route path="/employees" element={<EmployeesPage />} />
                <Route path="/employees/:id" element={<EmployeeProfilePage />} />
              </Route>

              <Route element={<RequirePermission permission="department.view" />}>
                <Route path="/employees/departments" element={<DepartmentsPage />} />
              </Route>

              <Route element={<RequirePermission permission="position.view" />}>
                <Route path="/employees/positions" element={<PositionsPage />} />
              </Route>

              <Route element={<RequirePermission permission="team.view" />}>
                <Route path="/teams" element={<TeamsPage />} />
                <Route path="/teams/:id" element={<TeamDetailPage />} />
              </Route>

              <Route element={<RequirePermission permission="site_assignment.view" />}>
                <Route path="/site-assignments" element={<SiteAssignmentsPage />} />
                <Route path="/site-operations" element={<SiteOperationsPage />} />
              </Route>

              <Route element={<RequirePermission permission="scheduling.view" />}>
                <Route path="/schedule" element={<SchedulePage />} />
              </Route>

              <Route element={<RequirePermission permission="scheduling.manage" />}>
                <Route path="/schedule/definitions" element={<ShiftDefinitionsPage />} />
                <Route path="/schedule/recommendations" element={<SchedulingRecommendationsPage />} />
              </Route>

              <Route element={<RequirePermission permission="availability.view" />}>
                <Route path="/schedule/availability" element={<AvailabilityPage />} />
              </Route>

              <Route element={<RequirePermission permission="attendance.view" />}>
                <Route path="/attendance" element={<AttendancePage />} />
                <Route path="/attendance/mine" element={<MyAttendancePage />} />
              </Route>

              <Route element={<RequirePermission permission="attendance.manage" />}>
                <Route path="/attendance/corrections" element={<AttendanceCorrectionsPage />} />
              </Route>

              <Route element={<RequirePermission permission="leave.view" />}>
                <Route path="/leave" element={<MyLeavePage />} />
                <Route path="/leave/team" element={<TeamLeavePage />} />
              </Route>

              <Route element={<RequirePermission permission="leave.approve" />}>
                <Route path="/leave/management" element={<LeaveManagementPage />} />
              </Route>

              <Route element={<RequirePermission permission="leave.manage" />}>
                <Route path="/leave/configuration" element={<LeaveConfigurationPage />} />
              </Route>

              <Route element={<RequirePermission permission="task.view" />}>
                <Route path="/tasks" element={<MyTasksPage />} />
              </Route>

              <Route element={<RequirePermission permission="task.manage" />}>
                <Route path="/tasks/management" element={<TaskManagementPage />} />
              </Route>

              <Route element={<RequirePermission permission="document.view" />}>
                <Route path="/documents" element={<MyDocumentsPage />} />
              </Route>

              <Route element={<RequirePermission permission="document.manage" />}>
                <Route path="/documents/manage" element={<EmployeeDocumentsPage />} />
              </Route>

              <Route element={<RequirePermission permission="incident.view" />}>
                <Route path="/incidents" element={<IncidentsPage />} />
              </Route>

              <Route element={<RequirePermission permission="compliance.view" />}>
                <Route path="/compliance" element={<CompliancePage />} />
              </Route>

              <Route element={<RequirePermission permission="asset.view" />}>
                <Route path="/assets" element={<AssetsPage />} />
              </Route>

              <Route element={<RequirePermission permission="inventory.view" />}>
                <Route path="/inventory" element={<InventoryPage />} />
              </Route>

              <Route element={<RequirePermission permission="procurement.view" />}>
                <Route path="/procurement" element={<ProcurementPage />} />
              </Route>

              <Route element={<RequirePermission permission="development.view" />}>
                <Route path="/development" element={<MyDevelopmentPage />} />
              </Route>

              <Route element={<RequirePermission permission="development.manage" />}>
                <Route path="/development/manage" element={<WorkforceDevelopmentPage />} />
              </Route>

              <Route element={<RequirePermission permission="reports.view" />}>
                <Route path="/reports" element={<ReportsPage />} />
              </Route>

              <Route element={<RequirePermission permission="org_structure.view" />}>
                <Route path="/regions" element={<RegionsPage />} />
                <Route path="/regions/:id" element={<RegionDetailPage />} />
                <Route path="/clients" element={<ClientsPage />} />
                <Route path="/clients/:id" element={<ClientDetailPage />} />
                <Route path="/sites" element={<SitesPage />} />
                <Route path="/sites/:id" element={<SiteDetailPage />} />
                <Route path="/contracts" element={<ContractsPage />} />
                <Route path="/contracts/:id" element={<ContractDetailPage />} />
              </Route>

              <Route element={<RequirePermission permission="patrol.view" />}>
                <Route path="/patrols" element={<MyPatrolsPage />} />
              </Route>

              <Route element={<RequirePermission permission="command_centre.view" />}>
                <Route path="/patrols/oversight" element={<PatrolOversightPage />} />
                <Route path="/command-centre" element={<CommandCentrePage />} />
                <Route path="/command-centre/alerts" element={<OperationalAlertsPage />} />
              </Route>

              <Route element={<RequirePermission permission="emergency.view" />}>
                <Route path="/emergencies" element={<EmergencyResponsePage />} />
              </Route>

              <Route element={<RequirePermission permission="intelligence.view" />}>
                <Route path="/intelligence" element={<AiAssistantPage />} />
              </Route>
            </Route>
          </Route>
        </Route>

        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </Suspense>
  );
}
