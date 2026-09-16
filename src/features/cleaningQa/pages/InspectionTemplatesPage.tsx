import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useInspectionTemplates, useInspectionTemplateItems } from '@/features/cleaningQa/hooks/useCleaningQa';
import { cleaningQaService } from '@/features/cleaningQa/services/cleaningQaService';
import { getDbErrorMessage } from '@/lib/dbErrors';

/** Deterministic weighted scoring templates — area/criterion/max_score/weight. complete_inspection() computes SUM(score*weight)/SUM(max_score*weight)*100 server-side, never an AI judgement call. */
export function InspectionTemplatesPage() {
  const { can } = usePermissions();
  const canManage = can('inspection.manage');
  const organization = useCurrentOrganization();
  const { templates, isLoading, error, refetch } = useInspectionTemplates(organization?.id);

  const [selectedTemplateId, setSelectedTemplateId] = useState<string | null>(null);
  const { items, refetch: refetchItems } = useInspectionTemplateItems(selectedTemplateId ?? undefined);

  const [name, setName] = useState('');
  const [passThreshold, setPassThreshold] = useState('80');
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  const [areaLabel, setAreaLabel] = useState('');
  const [criterion, setCriterion] = useState('');
  const [maxScore, setMaxScore] = useState('10');
  const [weight, setWeight] = useState('1');
  const [isAddingItem, setIsAddingItem] = useState(false);
  const [itemError, setItemError] = useState<string | null>(null);

  const handleCreateTemplate = async () => {
    if (!organization || !name.trim()) return;
    setIsCreating(true);
    setCreateError(null);
    try {
      const template = await cleaningQaService.createTemplate(organization.id, name.trim(), Number(passThreshold));
      setName('');
      await refetch();
      setSelectedTemplateId(template.id);
    } catch (err) {
      setCreateError(getDbErrorMessage(err, 'Failed to create the template.'));
    } finally {
      setIsCreating(false);
    }
  };

  const handleAddItem = async () => {
    if (!organization || !selectedTemplateId || !areaLabel.trim() || !criterion.trim()) return;
    setIsAddingItem(true);
    setItemError(null);
    try {
      await cleaningQaService.addTemplateItem(organization.id, selectedTemplateId, areaLabel.trim(), criterion.trim(), Number(maxScore), Number(weight));
      setAreaLabel('');
      setCriterion('');
      await refetchItems();
    } catch (err) {
      setItemError(getDbErrorMessage(err, 'Failed to add this criterion.'));
    } finally {
      setIsAddingItem(false);
    }
  };

  const selectedTemplate = templates.find((template) => template.id === selectedTemplateId);

  return (
    <PageContainer>
      <PageHeader title="QA Templates" description="Cleaning quality inspection templates — deterministic, weighted scoring per criterion." />
      <ErrorAlert message={error} />

      {!organization ? (
        <NoActiveOrganizationNotice resource="inspection templates" />
      ) : isLoading ? (
        <LoadingBlock label="Loading templates…" />
      ) : (
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <div className="flex flex-col gap-3">
            <h2 className="text-base font-semibold text-content-primary">Templates</h2>
            <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
              {templates.length === 0 && <p className="px-4 py-8 text-center text-sm text-content-tertiary">No templates yet.</p>}
              {templates.map((template) => (
                <button
                  key={template.id}
                  type="button"
                  onClick={() => setSelectedTemplateId(template.id)}
                  className={`focus-ring flex items-center justify-between px-4 py-3 text-left text-sm ${selectedTemplateId === template.id ? 'bg-brand-50 dark:bg-brand-500/10' : ''}`}
                >
                  <span className="font-medium text-content-primary">{template.name}</span>
                  <span className="text-xs text-content-tertiary">Pass ≥ {template.passThreshold}%</span>
                </button>
              ))}
            </div>
            {canManage && (
              <div className="flex flex-wrap items-end gap-2 rounded-card border border-border bg-surface-raised p-4">
                <ErrorAlert message={createError} />
                <TextField label="Template name" placeholder="Standard Office Clean" value={name} onChange={(event) => setName(event.target.value)} />
                <TextField label="Pass threshold %" type="number" min={0} max={100} value={passThreshold} onChange={(event) => setPassThreshold(event.target.value)} />
                <Button variant="secondary" onClick={() => void handleCreateTemplate()} isLoading={isCreating} disabled={!name.trim()}>
                  Add template
                </Button>
              </div>
            )}
          </div>

          <div className="flex flex-col gap-3">
            <h2 className="text-base font-semibold text-content-primary">{selectedTemplate ? `${selectedTemplate.name} — criteria` : 'Select a template'}</h2>
            {selectedTemplateId && (
              <>
                <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
                  {items.length === 0 && <p className="px-4 py-8 text-center text-sm text-content-tertiary">No criteria yet.</p>}
                  {items.map((item) => (
                    <div key={item.id} className="flex items-center justify-between px-4 py-3 text-sm">
                      <div>
                        <span className="font-medium text-content-primary">{item.areaLabel}</span>
                        <span className="ml-2 text-content-secondary">{item.criterion}</span>
                      </div>
                      <span className="text-xs text-content-tertiary">
                        max {item.maxScore} · weight {item.weight}
                      </span>
                    </div>
                  ))}
                </div>
                {canManage && (
                  <div className="flex flex-wrap items-end gap-2 rounded-card border border-border bg-surface-raised p-4">
                    <ErrorAlert message={itemError} />
                    <TextField label="Area" placeholder="Reception" value={areaLabel} onChange={(event) => setAreaLabel(event.target.value)} />
                    <TextField label="Criterion" placeholder="Floor cleanliness" value={criterion} onChange={(event) => setCriterion(event.target.value)} />
                    <TextField label="Max score" type="number" min={1} value={maxScore} onChange={(event) => setMaxScore(event.target.value)} />
                    <TextField label="Weight" type="number" min={0.01} step="0.01" value={weight} onChange={(event) => setWeight(event.target.value)} />
                    <Button variant="secondary" onClick={() => void handleAddItem()} isLoading={isAddingItem} disabled={!areaLabel.trim() || !criterion.trim()}>
                      Add criterion
                    </Button>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      )}
    </PageContainer>
  );
}
