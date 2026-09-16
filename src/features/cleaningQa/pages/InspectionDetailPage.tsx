import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { usePermissions } from '@/hooks/usePermissions';
import { useAuth } from '@/features/auth/context/authContext';
import { useInspection, useInspectionResults, useDefects } from '@/features/cleaningQa/hooks/useCleaningQa';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useSite } from '@/features/orgStructure/hooks/useSites';
import { cleaningQaService } from '@/features/cleaningQa/services/cleaningQaService';
import type { InspectionTemplateItem } from '@/features/cleaningQa/types/cleaningQa.types';
import type { DefectSeverity, InspectionStatus } from '@/features/cleaningQa/types/cleaningQa.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_TONE: Record<InspectionStatus, StatusTone> = {
  scheduled: 'neutral',
  in_progress: 'info',
  completed: 'warning',
  closed: 'success',
};

const SEVERITY_OPTIONS: DefectSeverity[] = ['low', 'medium', 'high', 'critical'];

export function InspectionDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const { user } = useAuth();
  const canManage = can('inspection.manage');
  const { inspection, isLoading, error, refetch } = useInspection(id);
  const { results, refetch: refetchResults } = useInspectionResults(id);
  const { defects, refetch: refetchDefects } = useDefects(id);
  const { client } = useClient(inspection?.clientId);
  const { site } = useSite(inspection?.siteId);

  const [templateItems, setTemplateItems] = useState<InspectionTemplateItem[]>([]);
  const [scores, setScores] = useState<Record<string, string>>({});
  const [actionError, setActionError] = useState<string | null>(null);
  const [isActing, setIsActing] = useState(false);

  const [defectDescription, setDefectDescription] = useState('');
  const [defectSeverity, setDefectSeverity] = useState<DefectSeverity>('medium');
  const [defectArea, setDefectArea] = useState('');

  useEffect(() => {
    if (inspection?.templateId) {
      void cleaningQaService.getTemplateItems(inspection.templateId).then(setTemplateItems);
    }
  }, [inspection?.templateId]);

  if (isLoading) return <FullScreenSpinner label="Loading inspection…" />;
  if (error) return <FullScreenNotice title="Something went wrong" message={error} />;
  if (!inspection) {
    return (
      <FullScreenNotice
        title="Inspection not found"
        message="This inspection doesn't exist, or you don't have access to view it."
        action={
          <Link to="/inspections" className="focus-ring self-start rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Cleaning QA
          </Link>
        }
      />
    );
  }

  const runAction = async (action: () => Promise<unknown>, failureMessage: string) => {
    setIsActing(true);
    setActionError(null);
    try {
      await action();
      await Promise.all([refetch(), refetchResults(), refetchDefects()]);
    } catch (err) {
      setActionError(getDbErrorMessage(err, failureMessage));
    } finally {
      setIsActing(false);
    }
  };

  const resultByItem = (itemId: string) => results.find((result) => result.templateItemId === itemId);
  const openDefects = defects.filter((defect) => defect.status === 'open' || defect.status === 'in_progress');

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button type="button" onClick={() => navigate('/inspections')} className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary">
        ← Back to Cleaning QA
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{site?.name ?? 'Inspection'}</h1>
            <p className="text-sm text-content-secondary">{client?.name ?? 'No client'}</p>
          </div>
          <StatusBadge label={inspection.status.replace(/_/g, ' ')} tone={STATUS_TONE[inspection.status]} />
        </div>

        {inspection.overallScore !== null && (
          <p className="mt-3 text-sm text-content-primary">
            Overall score: <span className="font-semibold">{inspection.overallScore}%</span> — {inspection.passed ? 'Passed' : 'Failed'}
          </p>
        )}

        <ErrorAlert message={actionError} />

        {canManage && (
          <div className="mt-4 flex flex-wrap gap-2 border-t border-border pt-4">
            {inspection.status === 'scheduled' && (
              <Button variant="secondary" isLoading={isActing} onClick={() => void runAction(() => cleaningQaService.startInspection(inspection.id), 'Failed to start this inspection.')}>
                Start inspection
              </Button>
            )}
            {inspection.status === 'in_progress' && (
              <Button isLoading={isActing} onClick={() => void runAction(() => cleaningQaService.completeInspection(inspection.id), 'Failed to complete this inspection — every criterion needs a submitted score first.')}>
                Complete inspection
              </Button>
            )}
            {inspection.status === 'completed' && (
              <Button
                isLoading={isActing}
                disabled={openDefects.length > 0}
                onClick={() => void runAction(() => cleaningQaService.closeInspection(inspection.id), 'Failed to close this inspection.')}
              >
                Close inspection{openDefects.length > 0 ? ` (${openDefects.length} open defect${openDefects.length > 1 ? 's' : ''})` : ''}
              </Button>
            )}
          </div>
        )}
      </div>

      {inspection.status === 'in_progress' && canManage && (
        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-content-primary">Criteria</h2>
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {templateItems.map((item) => {
              const existing = resultByItem(item.id);
              return (
                <div key={item.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm">
                  <div>
                    <span className="font-medium text-content-primary">{item.areaLabel}</span>
                    <span className="ml-2 text-content-secondary">{item.criterion}</span>
                    <span className="ml-2 text-xs text-content-tertiary">(max {item.maxScore}, weight {item.weight})</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="number"
                      min={0}
                      max={item.maxScore}
                      step="0.5"
                      value={scores[item.id] ?? existing?.score ?? ''}
                      onChange={(event) => setScores((prev) => ({ ...prev, [item.id]: event.target.value }))}
                      className="focus-ring h-9 w-20 rounded-lg border border-border-strong bg-surface-raised px-2 text-right"
                    />
                    <Button
                      variant="secondary"
                      className="h-9 px-3 text-xs"
                      isLoading={isActing}
                      disabled={!scores[item.id] && existing === undefined}
                      onClick={() =>
                        void runAction(
                          () => cleaningQaService.submitResult(inspection.id, item.id, Number(scores[item.id] ?? existing?.score ?? 0)),
                          'Failed to submit this score.',
                        )
                      }
                    >
                      {existing ? 'Update' : 'Submit'}
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {(inspection.status === 'completed' || inspection.status === 'closed') && (
        <section className="flex flex-col gap-3">
          <h2 className="text-base font-semibold text-content-primary">Defects</h2>
          {defects.length === 0 ? (
            <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">No defects recorded.</p>
          ) : (
            <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
              {defects.map((defect) => (
                <div key={defect.id} className="flex flex-col gap-2 px-4 py-3 text-sm">
                  <div className="flex items-center justify-between">
                    <span className="font-medium text-content-primary">{defect.description}</span>
                    <span className="text-xs capitalize text-content-tertiary">{defect.severity}</span>
                  </div>
                  <span className="text-xs capitalize text-content-secondary">{defect.status.replace(/_/g, ' ')}</span>
                  {canManage && (defect.status === 'open' || defect.status === 'in_progress') && (
                    <ResolveDefectRow
                      defectId={defect.id}
                      isActing={isActing}
                      onResolve={(notes, action) => void runAction(() => cleaningQaService.resolveDefect(defect.id, notes, action), 'Failed to resolve this defect.')}
                    />
                  )}
                  {canManage && defect.status === 'resolved' && (
                    <Button
                      variant="secondary"
                      className="h-8 w-fit px-3 text-xs"
                      isLoading={isActing}
                      disabled={defect.resolvedBy === user?.id}
                      onClick={() => void runAction(() => cleaningQaService.verifyDefect(defect.id), 'Failed to verify this defect.')}
                    >
                      {defect.resolvedBy === user?.id ? "Can't verify your own resolution" : 'Verify'}
                    </Button>
                  )}
                  {canManage && defect.status === 'verified' && !defect.reinspectionId && (
                    <Button
                      variant="ghost"
                      className="h-8 w-fit px-3 text-xs"
                      isLoading={isActing}
                      onClick={() =>
                        void runAction(async () => {
                          const reinspection = await cleaningQaService.scheduleReinspection(defect.id);
                          navigate(`/inspections/${reinspection.id}`);
                        }, 'Failed to schedule a reinspection.')
                      }
                    >
                      Schedule reinspection
                    </Button>
                  )}
                </div>
              ))}
            </div>
          )}
          {canManage && inspection.status === 'completed' && (
            <div className="flex flex-wrap items-end gap-2 rounded-card border border-border bg-surface-raised p-4">
              <TextField label="Description" value={defectDescription} onChange={(event) => setDefectDescription(event.target.value)} />
              <TextField label="Area" value={defectArea} onChange={(event) => setDefectArea(event.target.value)} />
              <label className="flex flex-col gap-1 text-sm">
                Severity
                <select value={defectSeverity} onChange={(event) => setDefectSeverity(event.target.value as DefectSeverity)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
                  {SEVERITY_OPTIONS.map((severity) => (
                    <option key={severity} value={severity}>
                      {severity}
                    </option>
                  ))}
                </select>
              </label>
              <Button
                variant="secondary"
                isLoading={isActing}
                disabled={!defectDescription.trim()}
                onClick={() =>
                  void runAction(async () => {
                    await cleaningQaService.createDefect(inspection.id, defectDescription.trim(), defectSeverity, defectArea.trim() || undefined);
                    setDefectDescription('');
                    setDefectArea('');
                  }, 'Failed to log this defect.')
                }
              >
                Log defect
              </Button>
            </div>
          )}
        </section>
      )}
    </div>
  );
}

function ResolveDefectRow({ defectId, isActing, onResolve }: { defectId: string; isActing: boolean; onResolve: (notes: string, correctiveAction?: string) => void }) {
  const [notes, setNotes] = useState('');
  return (
    <div className="flex flex-wrap items-end gap-2">
      <TextField label="Resolution notes" value={notes} onChange={(event) => setNotes(event.target.value)} />
      <Button
        variant="secondary"
        className="h-9 px-3 text-xs"
        isLoading={isActing}
        disabled={!notes.trim()}
        onClick={() => {
          onResolve(notes.trim());
          setNotes('');
        }}
        data-defect-id={defectId}
      >
        Resolve
      </Button>
    </div>
  );
}
