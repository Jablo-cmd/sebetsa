import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useMyEmployee } from '@/features/employees/hooks/useMyEmployee';
import { workforceDevelopmentService } from '@/features/workforceDevelopment/services/workforceDevelopmentService';
import { PERFORMANCE_STATUS_LABELS } from '@/features/workforceDevelopment/types/workforceDevelopment.types';
import type { EmployeeSkill, EmployeeQualification, TrainingEnrollment, PerformanceReview, DevelopmentAction } from '@/features/workforceDevelopment/types/workforceDevelopment.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** Employee self-service: their own skills, qualifications, training,
 * performance review acknowledgement, and development actions — read-only
 * except for their own review acknowledgement and their own development
 * action status, matching the server-side authorization exactly. */
export function MyDevelopmentPage() {
  const { data: employee, isLoading: employeeLoading, error: employeeError } = useMyEmployee();
  const [skills, setSkills] = useState<EmployeeSkill[]>([]);
  const [qualifications, setQualifications] = useState<EmployeeQualification[]>([]);
  const [enrollments, setEnrollments] = useState<TrainingEnrollment[]>([]);
  const [reviews, setReviews] = useState<PerformanceReview[]>([]);
  const [actions, setActions] = useState<DevelopmentAction[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [comments, setComments] = useState('');

  const load = useCallback(async () => {
    if (!employee) return;
    try {
      const [s, q, e, r, a] = await Promise.all([
        workforceDevelopmentService.getEmployeeSkills(employee.id),
        workforceDevelopmentService.getQualifications(employee.id),
        workforceDevelopmentService.getEnrollments(employee.id),
        workforceDevelopmentService.getReviews(employee.id),
        workforceDevelopmentService.getDevelopmentActions(employee.id),
      ]);
      setSkills(s);
      setQualifications(q);
      setEnrollments(e);
      setReviews(r);
      setActions(a);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load your development record.'));
    }
  }, [employee]);

  useEffect(() => {
    void load();
  }, [load]);

  const handleAcknowledge = async (reviewId: string) => {
    setError(null);
    try {
      await workforceDevelopmentService.advanceReview(reviewId, 'acknowledgement', { employeeComments: comments || undefined });
      setComments('');
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to acknowledge the review.'));
    }
  };

  const handleActionStatus = async (id: string, status: DevelopmentAction['status']) => {
    setError(null);
    try {
      await workforceDevelopmentService.updateDevelopmentActionStatus(id, status);
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to update the development action.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader title="My Development" description="Your skills, qualifications, training and performance record." />

      <ErrorAlert message={employeeError ?? error} />

      {employeeLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : (
        <div className="mt-4 flex flex-col gap-6">
          <section>
            <h2 className="text-base font-semibold text-content-primary">Skills</h2>
            {skills.length === 0 ? (
              <p className="mt-2 text-sm text-content-tertiary">No skills recorded yet.</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-1 text-sm">
                {skills.map((s) => (
                  <li key={s.id} className="text-content-primary">{s.proficiencyLevel} {s.verifiedAt ? '(verified)' : '(unverified)'}</li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Qualifications & certifications</h2>
            {qualifications.length === 0 ? (
              <p className="mt-2 text-sm text-content-tertiary">None on file yet.</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-1 text-sm">
                {qualifications.map((q) => (
                  <li key={q.id} className="text-content-primary">{q.name} — {q.status}{q.expiryDate ? ` (expires ${q.expiryDate})` : ''}</li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Training</h2>
            {enrollments.length === 0 ? (
              <p className="mt-2 text-sm text-content-tertiary">No training enrolments yet.</p>
            ) : (
              <ul className="mt-2 flex flex-col gap-1 text-sm">
                {enrollments.map((e) => (
                  <li key={e.id} className="text-content-primary">{e.status}</li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Performance reviews</h2>
            {reviews.length === 0 ? (
              <p className="mt-2 text-sm text-content-tertiary">No performance reviews yet.</p>
            ) : (
              <div className="mt-2 flex flex-col gap-2">
                {reviews.map((review) => (
                  <div key={review.id} className="rounded-xl border border-border bg-surface-raised p-4">
                    <p className="text-sm font-medium text-content-primary">{review.reviewPeriodStart} to {review.reviewPeriodEnd} — {PERFORMANCE_STATUS_LABELS[review.status]}</p>
                    {review.managerComments && <p className="mt-1 text-sm text-content-secondary">{review.managerComments}</p>}
                    {review.status === 'employee_review' && (
                      <div className="mt-2 flex gap-2">
                        <TextField label="Your comments (optional)" value={comments} onChange={(event) => setComments(event.target.value)} />
                        <Button onClick={() => void handleAcknowledge(review.id)}>Acknowledge</Button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>

          <section>
            <h2 className="text-base font-semibold text-content-primary">Development actions</h2>
            {actions.length === 0 ? (
              <p className="mt-2 text-sm text-content-tertiary">No development actions yet.</p>
            ) : (
              <div className="mt-2 flex flex-col gap-2">
                {actions.map((action) => (
                  <div key={action.id} className="flex items-center justify-between rounded-xl border border-border bg-surface-raised p-4">
                    <div>
                      <p className="text-sm text-content-primary">{action.goal}</p>
                      <p className="text-xs text-content-tertiary">{action.status}{action.targetDate ? ` — target ${action.targetDate}` : ''}</p>
                    </div>
                    {action.status !== 'completed' && (
                      <Button variant="ghost" onClick={() => void handleActionStatus(action.id, 'completed')}>Mark complete</Button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      )}
    </PageContainer>
  );
}
