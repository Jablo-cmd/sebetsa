import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { useLeaveTypes } from '@/features/leave/hooks/useLeaveTypes';
import { leaveTypeService } from '@/features/leave/services/leaveTypeService';
import { leaveBalanceService } from '@/features/leave/services/leaveBalanceService';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** leave.manage only: leave-type catalogue, and manual balance adjustments.
 * Not a policy DSL or an accrual engine — see the approved Phase H
 * architecture §11/§27: adjustments are the one manual lever this phase
 * exposes, always through the ledger (adjust_leave_balance), never a direct
 * write to leave_balances.remaining (which is a generated column anyway). */
export function LeaveConfigurationPage() {
  const organization = useCurrentOrganization();
  const { leaveTypes, isLoading, error, refetch } = useLeaveTypes(organization?.id, true);

  const [newTypeName, setNewTypeName] = useState('');
  const [newTypeError, setNewTypeError] = useState<string | null>(null);
  const [isCreatingType, setIsCreatingType] = useState(false);

  const [employeeSearch, setEmployeeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedEmployee, setSelectedEmployee] = useState<EmployeeCandidate | null>(null);
  const [adjustLeaveTypeId, setAdjustLeaveTypeId] = useState('');
  const [adjustAmount, setAdjustAmount] = useState('');
  const [adjustNote, setAdjustNote] = useState('');
  const [adjustError, setAdjustError] = useState<string | null>(null);
  const [adjustSuccess, setAdjustSuccess] = useState<string | null>(null);
  const [isAdjusting, setIsAdjusting] = useState(false);

  if (!organization) return <NoActiveOrganizationNotice resource="leave" />;

  const handleCreateType = async () => {
    if (!newTypeName.trim()) return;
    setIsCreatingType(true);
    setNewTypeError(null);
    try {
      await leaveTypeService.createLeaveType(organization.id, {
        name: newTypeName.trim(),
        isPaid: true,
        requiresDocumentation: false,
        defaultAnnualDays: null,
      });
      setNewTypeName('');
      void refetch();
    } catch (err) {
      setNewTypeError(getDbErrorMessage(err, 'Failed to create the leave type.'));
    } finally {
      setIsCreatingType(false);
    }
  };

  const handleDeactivate = async (id: string, currentStatus: string) => {
    await leaveTypeService.setLeaveTypeStatus(id, currentStatus === 'active' ? 'inactive' : 'active');
    void refetch();
  };

  const searchEmployees = async (query: string) => {
    setEmployeeSearch(query);
    if (!organization) return;
    setCandidates(await employeeService.searchEmployeeCandidates(organization.id, query));
  };

  const handleAdjust = async () => {
    if (!selectedEmployee || !adjustLeaveTypeId || !adjustAmount) return;
    setIsAdjusting(true);
    setAdjustError(null);
    setAdjustSuccess(null);
    try {
      const result = await leaveBalanceService.adjustBalance(
        selectedEmployee.id,
        adjustLeaveTypeId,
        new Date().getFullYear(),
        Number(adjustAmount),
        adjustNote.trim() || undefined,
      );
      setAdjustSuccess(`Balance updated — remaining now ${result.remaining} day(s).`);
      setAdjustAmount('');
      setAdjustNote('');
    } catch (err) {
      setAdjustError(getDbErrorMessage(err, 'Failed to adjust the balance.'));
    } finally {
      setIsAdjusting(false);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Leave Configuration" description="Manage leave types and adjust employee leave balances." />

      <ErrorAlert message={error} />

      <section className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
        <h2 className="text-sm font-semibold text-content-primary">Leave types</h2>

        <div className="mt-3 flex flex-wrap items-end gap-2">
          <TextField label="New leave type name" value={newTypeName} onChange={(event) => setNewTypeName(event.target.value)} />
          <Button onClick={() => void handleCreateType()} isLoading={isCreatingType}>
            Add
          </Button>
        </div>
        {newTypeError && <p className="mt-2 text-sm font-medium text-danger-600">{newTypeError}</p>}

        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-border text-xs uppercase text-content-secondary">
                <th className="px-3 py-2">Name</th>
                <th className="px-3 py-2">Paid</th>
                <th className="px-3 py-2">Requires docs</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                <tr>
                  <td colSpan={5} className="px-3 py-4 text-center text-content-secondary">
                    Loading…
                  </td>
                </tr>
              ) : (
                leaveTypes.map((type) => (
                  <tr key={type.id} className="border-b border-border last:border-0">
                    <td className="px-3 py-2.5">{type.name}</td>
                    <td className="px-3 py-2.5">{type.isPaid ? 'Yes' : 'No'}</td>
                    <td className="px-3 py-2.5">{type.requiresDocumentation ? 'Yes' : 'No'}</td>
                    <td className="px-3 py-2.5 capitalize">{type.status}</td>
                    <td className="px-3 py-2.5 text-right">
                      <Button variant="ghost" onClick={() => void handleDeactivate(type.id, type.status)}>
                        {type.status === 'active' ? 'Deactivate' : 'Reactivate'}
                      </Button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-6 rounded-xl border border-border bg-surface-raised p-4">
        <h2 className="text-sm font-semibold text-content-primary">Adjust an employee's leave balance</h2>
        <p className="mt-1 text-xs text-content-secondary">
          Every adjustment is written as a signed ledger transaction — never a direct edit of the balance.
        </p>

        <div className="mt-3 flex flex-col gap-3">
          <TextField
            label="Employee"
            placeholder="Search by name…"
            hint={selectedEmployee ? `Selected: ${selectedEmployee.firstName} ${selectedEmployee.lastName}` : undefined}
            value={employeeSearch}
            onChange={(event) => void searchEmployees(event.target.value)}
          />
          <div className="flex max-h-32 flex-col gap-1 overflow-y-auto">
            {candidates.map((candidate) => (
              <button
                key={candidate.id}
                type="button"
                onClick={() => setSelectedEmployee(candidate)}
                className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                  selectedEmployee?.id === candidate.id
                    ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                    : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
                }`}
              >
                {candidate.firstName} {candidate.lastName}
              </button>
            ))}
          </div>

          <div>
            <label htmlFor="adjust-leave-type" className="mb-1.5 block text-sm font-medium text-content-primary">
              Leave type
            </label>
            <select
              id="adjust-leave-type"
              className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
              value={adjustLeaveTypeId}
              onChange={(event) => setAdjustLeaveTypeId(event.target.value)}
            >
              <option value="">Select a leave type…</option>
              {leaveTypes.map((type) => (
                <option key={type.id} value={type.id}>
                  {type.name}
                </option>
              ))}
            </select>
          </div>

          <TextField
            label="Adjustment amount (days, may be negative)"
            type="number"
            step="0.5"
            value={adjustAmount}
            onChange={(event) => setAdjustAmount(event.target.value)}
          />
          <TextField label="Note" placeholder="Reason for this adjustment" value={adjustNote} onChange={(event) => setAdjustNote(event.target.value)} />

          {adjustError && <p className="text-sm font-medium text-danger-600">{adjustError}</p>}
          {adjustSuccess && <p className="text-sm font-medium text-success-600">{adjustSuccess}</p>}

          <div>
            <Button
              onClick={() => void handleAdjust()}
              isLoading={isAdjusting}
              disabled={!selectedEmployee || !adjustLeaveTypeId || !adjustAmount}
            >
              Apply adjustment
            </Button>
          </div>
        </div>
      </section>
    </PageContainer>
  );
}
