import { supabase } from '@/lib/supabase';
import type {
  SkillRow,
  EmployeeSkillRow,
  EmployeeQualificationRow,
  TrainingProgramRow,
  TrainingEnrollmentRow,
  PerformanceReviewRow,
  DevelopmentActionRow,
  ProficiencyLevelEnum,
  CredentialTypeEnum,
  TrainingEnrollmentStatusEnum,
  PerformanceReviewStatusEnum,
} from '@/lib/dbTypes';
import type {
  Skill,
  EmployeeSkill,
  EmployeeQualification,
  TrainingProgram,
  TrainingEnrollment,
  PerformanceReview,
  DevelopmentAction,
} from '@/features/workforceDevelopment/types/workforceDevelopment.types';

const toSkill = (row: SkillRow): Skill => ({ id: row.id, tenantId: row.tenant_id, name: row.name, category: row.category });

const toEmployeeSkill = (row: EmployeeSkillRow): EmployeeSkill => ({
  id: row.id,
  employeeId: row.employee_id,
  skillId: row.skill_id,
  proficiencyLevel: row.proficiency_level,
  verifiedBy: row.verified_by,
  verifiedAt: row.verified_at,
});

const toQualification = (row: EmployeeQualificationRow): EmployeeQualification => ({
  id: row.id,
  employeeId: row.employee_id,
  credentialType: row.credential_type,
  name: row.name,
  issuingOrganization: row.issuing_organization,
  issueDate: row.issue_date,
  expiryDate: row.expiry_date,
  status: row.status,
});

const toProgram = (row: TrainingProgramRow): TrainingProgram => ({ id: row.id, tenantId: row.tenant_id, name: row.name, description: row.description, category: row.category });

const toEnrollment = (row: TrainingEnrollmentRow): TrainingEnrollment => ({
  id: row.id,
  trainingProgramId: row.training_program_id,
  employeeId: row.employee_id,
  status: row.status,
  enrolledAt: row.enrolled_at,
  completedAt: row.completed_at,
  result: row.result,
});

const toReview = (row: PerformanceReviewRow): PerformanceReview => ({
  id: row.id,
  employeeId: row.employee_id,
  reviewerProfileId: row.reviewer_profile_id,
  reviewPeriodStart: row.review_period_start,
  reviewPeriodEnd: row.review_period_end,
  status: row.status,
  overallRating: row.overall_rating,
  managerComments: row.manager_comments,
  employeeComments: row.employee_comments,
  finalizedAt: row.finalized_at,
});

const toDevelopmentAction = (row: DevelopmentActionRow): DevelopmentAction => ({
  id: row.id,
  employeeId: row.employee_id,
  reviewId: row.review_id,
  goal: row.goal,
  ownerProfileId: row.owner_profile_id,
  targetDate: row.target_date,
  status: row.status as DevelopmentAction['status'],
});

async function getSkills(tenantId: string): Promise<Skill[]> {
  const { data, error } = await supabase.from('skills').select('*').eq('tenant_id', tenantId).order('name', { ascending: true });
  if (error) throw error;
  return data.map(toSkill);
}

async function createSkill(tenantId: string, name: string, category: string): Promise<Skill> {
  const { data, error } = await supabase.from('skills').insert({ tenant_id: tenantId, name, category }).select('*').single();
  if (error) throw error;
  return toSkill(data);
}

async function getEmployeeSkills(employeeId: string): Promise<EmployeeSkill[]> {
  const { data, error } = await supabase.from('employee_skills').select('*').eq('employee_id', employeeId);
  if (error) throw error;
  return data.map(toEmployeeSkill);
}

async function setEmployeeSkill(employeeId: string, skillId: string, level: ProficiencyLevelEnum): Promise<EmployeeSkill> {
  const { data, error } = await supabase.rpc('set_employee_skill', { p_employee_id: employeeId, p_skill_id: skillId, p_proficiency_level: level });
  if (error) throw error;
  return toEmployeeSkill(data);
}

async function verifyEmployeeSkill(employeeSkillId: string): Promise<EmployeeSkill> {
  const { data, error } = await supabase.rpc('verify_employee_skill', { p_employee_skill_id: employeeSkillId });
  if (error) throw error;
  return toEmployeeSkill(data);
}

async function getQualifications(employeeId: string): Promise<EmployeeQualification[]> {
  const { data, error } = await supabase.from('employee_qualifications').select('*').eq('employee_id', employeeId).order('expiry_date', { ascending: true, nullsFirst: false });
  if (error) throw error;
  return data.map(toQualification);
}

async function upsertQualification(input: { id?: string; employeeId: string; credentialType: CredentialTypeEnum; name: string; issuingOrganization?: string; issueDate?: string; expiryDate?: string }): Promise<EmployeeQualification> {
  const { data, error } = await supabase.rpc('upsert_employee_qualification', {
    p_id: input.id ?? null,
    p_employee_id: input.employeeId,
    p_credential_type: input.credentialType,
    p_name: input.name,
    p_issuing_organization: input.issuingOrganization ?? null,
    p_issue_date: input.issueDate ?? null,
    p_expiry_date: input.expiryDate ?? null,
  });
  if (error) throw error;
  return toQualification(data);
}

async function verifyQualification(id: string, approve: boolean): Promise<EmployeeQualification> {
  const { data, error } = await supabase.rpc('verify_employee_qualification', { p_id: id, p_approve: approve });
  if (error) throw error;
  return toQualification(data);
}

async function getTrainingPrograms(tenantId: string): Promise<TrainingProgram[]> {
  const { data, error } = await supabase.from('training_programs').select('*').eq('tenant_id', tenantId).order('name', { ascending: true });
  if (error) throw error;
  return data.map(toProgram);
}

async function createTrainingProgram(tenantId: string, name: string, category: string): Promise<TrainingProgram> {
  const { data, error } = await supabase.from('training_programs').insert({ tenant_id: tenantId, name, category }).select('*').single();
  if (error) throw error;
  return toProgram(data);
}

async function getEnrollments(employeeId: string): Promise<TrainingEnrollment[]> {
  const { data, error } = await supabase.from('training_enrollments').select('*').eq('employee_id', employeeId).order('enrolled_at', { ascending: false });
  if (error) throw error;
  return data.map(toEnrollment);
}

async function enrollTraining(trainingProgramId: string, employeeId: string): Promise<TrainingEnrollment> {
  const { data, error } = await supabase.rpc('enroll_employee_training', { p_training_program_id: trainingProgramId, p_employee_id: employeeId });
  if (error) throw error;
  return toEnrollment(data);
}

async function completeTraining(enrollmentId: string, status: TrainingEnrollmentStatusEnum, result?: string): Promise<TrainingEnrollment> {
  const { data, error } = await supabase.rpc('complete_employee_training', { p_enrollment_id: enrollmentId, p_status: status, p_result: result ?? null });
  if (error) throw error;
  return toEnrollment(data);
}

async function getReviews(employeeId: string): Promise<PerformanceReview[]> {
  const { data, error } = await supabase.from('performance_reviews').select('*').eq('employee_id', employeeId).order('review_period_start', { ascending: false });
  if (error) throw error;
  return data.map(toReview);
}

async function createReview(employeeId: string, reviewerProfileId: string, periodStart: string, periodEnd: string): Promise<PerformanceReview> {
  const { data, error } = await supabase.rpc('create_performance_review', { p_employee_id: employeeId, p_reviewer_profile_id: reviewerProfileId, p_review_period_start: periodStart, p_review_period_end: periodEnd });
  if (error) throw error;
  return toReview(data);
}

async function advanceReview(reviewId: string, newStatus: PerformanceReviewStatusEnum, options: { managerComments?: string; employeeComments?: string; overallRating?: number } = {}): Promise<PerformanceReview> {
  const { data, error } = await supabase.rpc('advance_performance_review', {
    p_review_id: reviewId,
    p_new_status: newStatus,
    p_manager_comments: options.managerComments ?? null,
    p_employee_comments: options.employeeComments ?? null,
    p_overall_rating: options.overallRating ?? null,
  });
  if (error) throw error;
  return toReview(data);
}

async function getDevelopmentActions(employeeId: string): Promise<DevelopmentAction[]> {
  const { data, error } = await supabase.from('development_actions').select('*').eq('employee_id', employeeId);
  if (error) throw error;
  return data.map(toDevelopmentAction);
}

async function addDevelopmentAction(employeeId: string, goal: string, ownerProfileId?: string, targetDate?: string): Promise<DevelopmentAction> {
  const { data, error } = await supabase.rpc('add_development_action', { p_employee_id: employeeId, p_goal: goal, p_owner_profile_id: ownerProfileId ?? null, p_target_date: targetDate ?? null });
  if (error) throw error;
  return toDevelopmentAction(data);
}

async function updateDevelopmentActionStatus(id: string, status: DevelopmentAction['status']): Promise<DevelopmentAction> {
  const { data, error } = await supabase.rpc('update_development_action_status', { p_id: id, p_status: status });
  if (error) throw error;
  return toDevelopmentAction(data);
}

export const workforceDevelopmentService = {
  getSkills,
  createSkill,
  getEmployeeSkills,
  setEmployeeSkill,
  verifyEmployeeSkill,
  getQualifications,
  upsertQualification,
  verifyQualification,
  getTrainingPrograms,
  createTrainingProgram,
  getEnrollments,
  enrollTraining,
  completeTraining,
  getReviews,
  createReview,
  advanceReview,
  getDevelopmentActions,
  addDevelopmentAction,
  updateDevelopmentActionStatus,
};
