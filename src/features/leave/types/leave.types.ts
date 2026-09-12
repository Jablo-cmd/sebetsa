import type { LeaveStatusEnum } from '@/lib/dbTypes';

export type LeaveStatus = LeaveStatusEnum;
export type HalfDayPeriod = 'am' | 'pm';

export interface LeaveType {
  id: string;
  tenantId: string;
  name: string;
  isPaid: boolean;
  requiresDocumentation: boolean;
  defaultAnnualDays: number | null;
  status: 'active' | 'inactive' | 'onboarding' | 'offboarded';
}

export interface LeavePolicy {
  id: string;
  tenantId: string;
  leaveTypeId: string;
  defaultAnnualDays: number | null;
  maxCarryOverDays: number | null;
  minNoticeDays: number;
  requiresDocumentation: boolean;
  maxConsecutiveDays: number | null;
}

export interface LeaveRequest {
  id: string;
  tenantId: string;
  employeeId: string;
  leaveTypeId: string;
  startDate: string;
  endDate: string;
  isHalfDay: boolean;
  halfDayPeriod: HalfDayPeriod | null;
  reason: string | null;
  status: LeaveStatus;
  decidedBy: string | null;
  decidedAt: string | null;
  decisionNotes: string | null;
  supportingDocumentRef: string | null;
  cancelledAt: string | null;
  cancelledBy: string | null;
  createdAt: string;
  updatedAt: string;
}

/** A narrower read-model for viewers who hold leave.view but not
 * leave.approve/leave.manage — omits reason/decisionNotes/supportingDocumentRef
 * (architecture §23: RLS is row-level, this is the field-level layer). */
export type LeaveRequestSummary = Omit<LeaveRequest, 'reason' | 'decisionNotes' | 'supportingDocumentRef'>;

export interface LeaveBalance {
  id: string;
  tenantId: string;
  employeeId: string;
  leaveTypeId: string;
  periodYear: number;
  openingBalance: number;
  accrued: number;
  used: number;
  pending: number;
  adjustment: number;
  carriedOver: number;
  remaining: number;
}

export interface LeaveBalanceTransaction {
  id: string;
  tenantId: string;
  employeeId: string;
  leaveTypeId: string;
  periodYear: number;
  transactionType: 'opening' | 'accrual' | 'usage' | 'adjustment' | 'carry_over' | 'reversal';
  amount: number;
  leaveRequestId: string | null;
  createdBy: string | null;
  createdAt: string;
}

export interface SubmitLeaveRequestInput {
  employeeId: string;
  leaveTypeId: string;
  startDate: string;
  endDate: string;
  isHalfDay: boolean;
  halfDayPeriod: HalfDayPeriod | null;
  reason: string | null;
  supportingDocumentRef: string | null;
}

export interface AffectedShift {
  id: string;
  siteId: string;
  employeeId: string;
  startsAt: string;
  endsAt: string;
  status: string;
}
