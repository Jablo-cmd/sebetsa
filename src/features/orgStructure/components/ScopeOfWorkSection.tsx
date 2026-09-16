import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { useSiteAreas } from '@/features/orgStructure/hooks/useSiteAreas';
import { useScopeOfWorkForContract } from '@/features/orgStructure/hooks/useScopeOfWork';
import { siteAreaService } from '@/features/orgStructure/services/siteAreaService';
import { scopeOfWorkService } from '@/features/orgStructure/services/scopeOfWorkService';
import type { Contract, Site, ScopeOfWorkItem } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface ScopeOfWorkSectionProps {
  contract: Contract;
  coveredSites: Site[];
  canManage: boolean;
}

/** CONTRACT -> SITE -> AREA -> TASK. Structured scope, not a free-text description — feeds the existing task_templates pipeline via create_task_template_from_scope_item(), never a second task system. */
export function ScopeOfWorkSection({ contract, coveredSites, canManage }: ScopeOfWorkSectionProps) {
  const { items: allItems, refetch: refetchItems } = useScopeOfWorkForContract(contract.id);

  if (coveredSites.length === 0) {
    return (
      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Scope of work</h2>
        <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
          Link a site to this contract before defining its scope of work.
        </p>
      </section>
    );
  }

  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-base font-semibold text-content-primary">Scope of work</h2>
      <div className="flex flex-col gap-4">
        {coveredSites.map((site) => (
          <SiteScopeBlock
            key={site.id}
            site={site}
            contract={contract}
            itemsForContract={allItems}
            canManage={canManage}
            onScopeChanged={refetchItems}
          />
        ))}
      </div>
    </section>
  );
}

function SiteScopeBlock({
  site,
  contract,
  itemsForContract,
  canManage,
  onScopeChanged,
}: {
  site: Site;
  contract: Contract;
  itemsForContract: ScopeOfWorkItem[];
  canManage: boolean;
  onScopeChanged: () => Promise<void>;
}) {
  const { areas, refetch: refetchAreas } = useSiteAreas(site.id);
  const [newAreaName, setNewAreaName] = useState('');
  const [isAddingArea, setIsAddingArea] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleAddArea = async () => {
    if (!newAreaName.trim()) return;
    setIsAddingArea(true);
    setError(null);
    try {
      await siteAreaService.createSiteArea(contract.tenantId, { siteId: site.id, name: newAreaName.trim() });
      setNewAreaName('');
      void refetchAreas();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to add the area.'));
    } finally {
      setIsAddingArea(false);
    }
  };

  return (
    <div className="rounded-card border border-border bg-surface-raised p-4">
      <h3 className="text-sm font-semibold text-content-primary">{site.name}</h3>
      <ErrorAlert message={error} />
      <div className="mt-3 flex flex-col gap-3">
        {areas.length === 0 ? (
          <p className="text-sm text-content-tertiary">No areas defined for this site yet.</p>
        ) : (
          areas.map((area) => (
            <AreaScopeBlock
              key={area.id}
              area={area}
              contract={contract}
              items={itemsForContract.filter((item) => item.siteAreaId === area.id)}
              canManage={canManage}
              onScopeChanged={onScopeChanged}
            />
          ))
        )}
      </div>
      {canManage && (
        <div className="mt-3 flex items-end gap-2 border-t border-border pt-3">
          <TextField label="New area" placeholder="e.g. Reception" value={newAreaName} onChange={(event) => setNewAreaName(event.target.value)} />
          <Button variant="secondary" onClick={() => void handleAddArea()} isLoading={isAddingArea} disabled={!newAreaName.trim()}>
            Add area
          </Button>
        </div>
      )}
    </div>
  );
}

function AreaScopeBlock({
  area,
  contract,
  items,
  canManage,
  onScopeChanged,
}: {
  area: { id: string; name: string };
  contract: Contract;
  items: ScopeOfWorkItem[];
  canManage: boolean;
  onScopeChanged: () => Promise<void>;
}) {
  const [taskName, setTaskName] = useState('');
  const [frequency, setFrequency] = useState('daily');
  const [isAdding, setIsAdding] = useState(false);
  const [generatingId, setGeneratingId] = useState<string | null>(null);
  const [generatedIds, setGeneratedIds] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);

  const handleAddItem = async () => {
    if (!taskName.trim()) return;
    setIsAdding(true);
    setError(null);
    try {
      await scopeOfWorkService.createScopeOfWorkItem(contract.tenantId, {
        contractId: contract.id,
        siteAreaId: area.id,
        taskName: taskName.trim(),
        frequency,
      });
      setTaskName('');
      await onScopeChanged();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to add the scope item.'));
    } finally {
      setIsAdding(false);
    }
  };

  const handleGenerate = async (itemId: string) => {
    setGeneratingId(itemId);
    setError(null);
    try {
      await scopeOfWorkService.generateTaskTemplate(itemId);
      setGeneratedIds((prev) => new Set(prev).add(itemId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to generate a task template from this scope item.'));
    } finally {
      setGeneratingId(null);
    }
  };

  return (
    <div className="rounded-lg border border-border-strong/60 p-3">
      <p className="text-xs font-medium uppercase tracking-wide text-content-tertiary">{area.name}</p>
      <ErrorAlert message={error} />
      {items.length === 0 ? (
        <p className="mt-1 text-sm text-content-tertiary">No scope items yet.</p>
      ) : (
        <ul className="mt-2 flex flex-col gap-2">
          {items.map((item) => (
            <li key={item.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-surface-sunken px-3 py-2 text-sm">
              <div>
                <span className="font-medium text-content-primary">{item.taskName}</span>
                {item.frequency && <span className="ml-2 text-xs capitalize text-content-tertiary">{item.frequency.replace('_', ' ')}</span>}
                {item.estimatedMinutes && <span className="ml-2 text-xs text-content-tertiary">{item.estimatedMinutes} min</span>}
              </div>
              {canManage && (
                <Button
                  variant="ghost"
                  className="h-8 text-xs"
                  onClick={() => void handleGenerate(item.id)}
                  isLoading={generatingId === item.id}
                  disabled={generatedIds.has(item.id)}
                >
                  {generatedIds.has(item.id) ? 'Task template created' : 'Generate task template'}
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
      {canManage && (
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <TextField label="Task" placeholder="Vacuum carpet" value={taskName} onChange={(event) => setTaskName(event.target.value)} />
          <label className="flex flex-col gap-1 text-xs">
            Frequency
            <select
              value={frequency}
              onChange={(event) => setFrequency(event.target.value)}
              className="focus-ring h-9 rounded-lg border border-border-strong bg-surface-raised px-2 text-sm"
            >
              <option value="daily">Daily</option>
              <option value="weekly">Weekly</option>
              <option value="monthly">Monthly</option>
              <option value="once_off">Once-off</option>
            </select>
          </label>
          <Button variant="secondary" className="h-9 text-xs" onClick={() => void handleAddItem()} isLoading={isAdding} disabled={!taskName.trim()}>
            Add scope item
          </Button>
        </div>
      )}
    </div>
  );
}
