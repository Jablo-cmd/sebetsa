import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { TextField } from '@/components/ui/TextField';
import { Button } from '@/components/ui/Button';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAuth } from '@/features/auth/context/authContext';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { workforceDevelopmentService } from '@/features/workforceDevelopment/services/workforceDevelopmentService';
import { PERFORMANCE_STATUS_LABELS } from '@/features/workforceDevelopment/types/workforceDevelopment.types';
import type { Skill, EmployeeSkill, EmployeeQualification, TrainingProgram, TrainingEnrollment, PerformanceReview } from '@/features/workforceDevelopment/types/workforceDevelopment.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** HR/operations-management tier (can_manage_employees): manage the skills
 * catalogue, verify qualifications, enroll employees in training, and run
 * performance reviews for a selected employee. */
export function WorkforceDevelopmentPage() {
  const organization = useCurrentOrganization();
  const { user } = useAuth();
  const [employeeSearch, setEmployeeSearch] = useState('');
  const [candidates, setCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedEmployee, setSelectedEmployee] = useState<EmployeeCandidate | null>(null);

  const [skills, setSkills] = useState<Skill[]>([]);
  const [employeeSkills, setEmployeeSkills] = useState<EmployeeSkill[]>([]);
  const [qualifications, setQualifications] = useState<EmployeeQualification[]>([]);
  const [programs, setPrograms] = useState<TrainingProgram[]>([]);
  const [enrollments, setEnrollments] = useState<TrainingEnrollment[]>([]);
  const [reviews, setReviews] = useState<PerformanceReview[]>([]);
  const [error, setError] = useState<string | null>(null);

  const [newSkillName, setNewSkillName] = useState('');
  const [newProgramName, setNewProgramName] = useState('');

  const loadCatalogues = useCallback(async () => {
    if (!organization) return;
    setSkills(await workforceDevelopmentService.getSkills(organization.id));
    setPrograms(await workforceDevelopmentService.getTrainingPrograms(organization.id));
  }, [organization]);

  const loadEmployeeData = useCallback(async () => {
    if (!selectedEmployee) return;
    try {
      const [es, q, e, r] = await Promise.all([
        workforceDevelopmentService.getEmployeeSkills(selectedEmployee.id),
        workforceDevelopmentService.getQualifications(selectedEmployee.id),
        workforceDevelopmentService.getEnrollments(selectedEmployee.id),
        workforceDevelopmentService.getReviews(selectedEmployee.id),
      ]);
      setEmployeeSkills(es);
      setQualifications(q);
      setEnrollments(e);
      setReviews(r);
    } catch (err) {
      setError(getDbErrorMessage(err, "Failed to load this employee's development record."));
    }
  }, [selectedEmployee]);

  useEffect(() => {
    void loadCatalogues();
  }, [loadCatalogues]);

  useEffect(() => {
    void loadEmployeeData();
  }, [loadEmployeeData]);

  if (!organization) return <NoActiveOrganizationNotice resource="workforce development" />;

  const searchEmployees = async (query: string) => {
    setEmployeeSearch(query);
    setCandidates(await employeeService.searchEmployeeCandidates(organization.id, query));
  };

  const handleCreateSkill = async () => {
    if (!newSkillName.trim()) return;
    try {
      await workforceDevelopmentService.createSkill(organization.id, newSkillName.trim(), 'general');
      setNewSkillName('');
      void loadCatalogues();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the skill.'));
    }
  };

  const handleCreateProgram = async () => {
    if (!newProgramName.trim()) return;
    try {
      await workforceDevelopmentService.createTrainingProgram(organization.id, newProgramName.trim(), 'general');
      setNewProgramName('');
      void loadCatalogues();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the training program.'));
    }
  };

  const handleVerifySkill = async (id: string) => {
    try {
      await workforceDevelopmentService.verifyEmployeeSkill(id);
      void loadEmployeeData();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to verify the skill.'));
    }
  };

  const handleVerifyQualification = async (id: string, approve: boolean) => {
    try {
      await workforceDevelopmentService.verifyQualification(id, approve);
      void loadEmployeeData();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to verify the qualification.'));
    }
  };

  const handleEnroll = async (programId: string) => {
    if (!selectedEmployee) return;
    try {
      await workforceDevelopmentService.enrollTraining(programId, selectedEmployee.id);
      void loadEmployeeData();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to enroll in training.'));
    }
  };

  const handleCreateReview = async () => {
    if (!selectedEmployee || !user) return;
    const now = new Date();
    const periodStart = new Date(now.getFullYear(), 0, 1).toISOString().slice(0, 10);
    const periodEnd = new Date(now.getFullYear(), 5, 30).toISOString().slice(0, 10);
    try {
      await workforceDevelopmentService.createReview(selectedEmployee.id, user.id, periodStart, periodEnd);
      void loadEmployeeData();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the performance review.'));
    }
  };

  const handleAdvanceReview = async (reviewId: string) => {
    const nextByStatus: Record<string, PerformanceReview['status']> = { draft: 'manager_review', manager_review: 'employee_review' };
    const review = reviews.find((r) => r.id === reviewId);
    const next = review ? nextByStatus[review.status] : undefined;
    if (!next) return;
    try {
      await workforceDevelopmentService.advanceReview(reviewId, next);
      void loadEmployeeData();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to advance the performance review.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Workforce Development" description="Skills, qualifications, training and performance for your workforce." />

      <ErrorAlert message={error} />

      <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-border bg-surface-raised p-4">
          <p className="text-sm font-medium text-content-primary">Skills catalogue</p>
          <ul className="mt-2 flex flex-col gap-1 text-sm text-content-secondary">
            {skills.map((s) => <li key={s.id}>{s.name}</li>)}
          </ul>
          <div className="mt-2 flex gap-2">
            <TextField label="New skill" value={newSkillName} onChange={(event) => setNewSkillName(event.target.value)} />
            <Button variant="secondary" onClick={() => void handleCreateSkill()} disabled={!newSkillName.trim()}>Add</Button>
          </div>
        </div>

        <div className="rounded-xl border border-border bg-surface-raised p-4">
          <p className="text-sm font-medium text-content-primary">Training programmes</p>
          <ul className="mt-2 flex flex-col gap-1 text-sm text-content-secondary">
            {programs.map((p) => <li key={p.id}>{p.name}</li>)}
          </ul>
          <div className="mt-2 flex gap-2">
            <TextField label="New programme" value={newProgramName} onChange={(event) => setNewProgramName(event.target.value)} />
            <Button variant="secondary" onClick={() => void handleCreateProgram()} disabled={!newProgramName.trim()}>Add</Button>
          </div>
        </div>
      </div>

      <div className="mt-6">
        <TextField
          label="Employee"
          placeholder="Search by name…"
          hint={selectedEmployee ? `Selected: ${selectedEmployee.firstName} ${selectedEmployee.lastName}` : undefined}
          value={employeeSearch}
          onChange={(event) => void searchEmployees(event.target.value)}
        />
        <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
          {candidates.map((candidate) => (
            <button
              key={candidate.id}
              type="button"
              onClick={() => setSelectedEmployee(candidate)}
              className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                selectedEmployee?.id === candidate.id ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10' : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
              }`}
            >
              {candidate.firstName} {candidate.lastName}
            </button>
          ))}
        </div>
      </div>

      {selectedEmployee && (
        <div className="mt-6 flex flex-col gap-6">
          <section>
            <h2 className="text-base font-semibold text-content-primary">Skills</h2>
            <div className="mt-2 flex flex-col gap-1">
              {employeeSkills.map((es) => (
                <div key={es.id} className="flex items-center justify-between rounded-lg border border-border bg-surface-raised px-3 py-2 text-sm">
                  <span>{skills.find((s) => s.id === es.skillId)?.name ?? es.skillId} — {es.proficiencyLevel} {es.verifiedAt ? '(verified)' : ''}</span>
                  {!es.verifiedAt && <Button variant="ghost" onClick={() => void handleVerifySkill(es.id)}>Verify</Button>}
                </div>
              ))}
            </div>
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Qualifications</h2>
            <div className="mt-2 flex flex-col gap-1">
              {qualifications.map((q) => (
                <div key={q.id} className="flex items-center justify-between rounded-lg border border-border bg-surface-raised px-3 py-2 text-sm">
                  <span>{q.name} — {q.status}</span>
                  {q.status === 'pending_verification' && (
                    <div className="flex gap-2">
                      <Button variant="ghost" onClick={() => void handleVerifyQualification(q.id, true)}>Approve</Button>
                      <Button variant="ghost" onClick={() => void handleVerifyQualification(q.id, false)}>Reject</Button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Training enrolments</h2>
            <div className="mt-2 flex flex-col gap-1">
              {enrollments.map((e) => (
                <p key={e.id} className="text-sm text-content-secondary">{programs.find((p) => p.id === e.trainingProgramId)?.name ?? e.trainingProgramId} — {e.status}</p>
              ))}
            </div>
            <div className="mt-2 flex flex-wrap gap-2">
              {programs.map((p) => (
                <Button key={p.id} variant="ghost" onClick={() => void handleEnroll(p.id)}>Enroll in {p.name}</Button>
              ))}
            </div>
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Performance reviews</h2>
            <div className="mt-2 flex flex-col gap-2">
              {reviews.map((review) => (
                <div key={review.id} className="flex items-center justify-between rounded-lg border border-border bg-surface-raised px-3 py-2 text-sm">
                  <span>{review.reviewPeriodStart} to {review.reviewPeriodEnd} — {PERFORMANCE_STATUS_LABELS[review.status]}</span>
                  {(review.status === 'draft' || review.status === 'manager_review') && (
                    <Button variant="ghost" onClick={() => void handleAdvanceReview(review.id)}>Advance</Button>
                  )}
                </div>
              ))}
            </div>
            <div className="mt-2">
              <Button variant="secondary" onClick={() => void handleCreateReview()}>Start a new review</Button>
            </div>
          </section>
        </div>
      )}
    </PageContainer>
  );
}
