import type {
  ProficiencyLevelEnum,
  CredentialTypeEnum,
  CredentialStatusEnum,
  TrainingEnrollmentStatusEnum,
  PerformanceReviewStatusEnum,
} from '@/lib/dbTypes';

export interface Skill {
  id: string;
  tenantId: string;
  name: string;
  category: string;
}

export interface EmployeeSkill {
  id: string;
  employeeId: string;
  skillId: string;
  proficiencyLevel: ProficiencyLevelEnum;
  verifiedBy: string | null;
  verifiedAt: string | null;
}

export interface EmployeeQualification {
  id: string;
  employeeId: string;
  credentialType: CredentialTypeEnum;
  name: string;
  issuingOrganization: string | null;
  issueDate: string | null;
  expiryDate: string | null;
  status: CredentialStatusEnum;
}

export interface TrainingProgram {
  id: string;
  tenantId: string;
  name: string;
  description: string | null;
  category: string;
}

export interface TrainingEnrollment {
  id: string;
  trainingProgramId: string;
  employeeId: string;
  status: TrainingEnrollmentStatusEnum;
  enrolledAt: string;
  completedAt: string | null;
  result: string | null;
}

export interface PerformanceReview {
  id: string;
  employeeId: string;
  reviewerProfileId: string | null;
  reviewPeriodStart: string;
  reviewPeriodEnd: string;
  status: PerformanceReviewStatusEnum;
  overallRating: number | null;
  managerComments: string | null;
  employeeComments: string | null;
  finalizedAt: string | null;
}

export interface DevelopmentAction {
  id: string;
  employeeId: string;
  reviewId: string | null;
  goal: string;
  ownerProfileId: string | null;
  targetDate: string | null;
  status: 'open' | 'in_progress' | 'completed';
}

export const PERFORMANCE_STATUS_LABELS: Record<PerformanceReviewStatusEnum, string> = {
  draft: 'Draft',
  manager_review: 'Manager review',
  employee_review: 'Awaiting employee review',
  acknowledgement: 'Awaiting acknowledgement',
  finalized: 'Finalized',
};
