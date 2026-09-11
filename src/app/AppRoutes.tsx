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
const AttendancePage = named(
  () => import('@/features/attendance/pages/AttendancePage'),
  'AttendancePage',
);
const NotificationsPage = named(
  () => import('@/features/notifications/pages/NotificationsPage'),
  'NotificationsPage',
);
const NotificationSettingsPage = named(
  () => import('@/features/notifications/pages/NotificationSettingsPage'),
  'NotificationSettingsPage',
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
                <Route path="/employees/departments" element={<DepartmentsPage />} />
                <Route path="/employees/:id" element={<EmployeeProfilePage />} />
              </Route>

              <Route element={<RequirePermission permission="attendance.view" />}>
                <Route path="/attendance" element={<AttendancePage />} />
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
