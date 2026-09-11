import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { EmployeeSelfSummary } from '@/features/employees/components/EmployeeSelfSummary';
import { MfaEnrollmentCard } from '@/features/mfa/components/MfaEnrollmentCard';

/**
 * Composition page only — layout, rendering order, and conditional
 * visibility. All data access, mapping, and authorization live in the
 * Employees domain this page composes; RLS (not this page) decides which
 * rows, if any, come back from the hook.
 */
export function MyProfilePage() {
  const employee = useMyEmployee();

  if (employee.isLoading) {
    return <FullScreenSpinner label="Loading your profile…" />;
  }

  const hasEmployeeRecord = Boolean(employee.data);

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6 px-4 py-8 sm:px-6">
      <div>
        <h1 className="text-2xl font-bold text-content-primary">My Profile</h1>
        <p className="mt-1 text-sm text-content-secondary">Records linked to your account.</p>
      </div>

      {hasEmployeeRecord && (
        <section className="flex flex-col gap-4">
          <h2 className="text-base font-semibold text-content-primary">Employee Information</h2>
          {employee.error ? (
            <div
              role="alert"
              className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
            >
              {employee.error}
            </div>
          ) : (
            employee.data && <EmployeeSelfSummary employee={employee.data} />
          )}
        </section>
      )}

      <MfaEnrollmentCard />
    </div>
  );
}
