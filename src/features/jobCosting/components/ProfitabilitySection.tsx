import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { jobCostingService, type ContractProfitability } from '@/features/jobCosting/services/jobCostingService';
import type { Contract, Site } from '@/features/orgStructure/types/orgStructure.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

function formatCurrency(value: number): string {
  return new Intl.NumberFormat('en-ZA', { style: 'currency', currency: 'ZAR' }).format(value);
}

function firstOfMonth(): string {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

interface ProfitabilitySectionProps {
  contract: Contract;
  tenantId: string;
  coveredSites: Site[];
  canView: boolean;
}

/** Revenue - Labour - Consumables - Equipment - Other = Gross Contribution, computed entirely server-side from real invoices/attendance/inventory/cost_entries — never a fabricated percentage. Commercially sensitive: gated on job_costing.view, not shown to operational tiers below org-structure. */
export function ProfitabilitySection({ contract, tenantId, coveredSites, canView }: ProfitabilitySectionProps) {
  const [periodStart, setPeriodStart] = useState(firstOfMonth());
  const [periodEnd, setPeriodEnd] = useState(today());
  const [result, setResult] = useState<ContractProfitability | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [costSiteId, setCostSiteId] = useState('');
  const [costCategory, setCostCategory] = useState<'equipment' | 'other'>('other');
  const [costDescription, setCostDescription] = useState('');
  const [costAmount, setCostAmount] = useState('');
  const [costDate, setCostDate] = useState(today());
  const [isSavingCost, setIsSavingCost] = useState(false);
  const [costError, setCostError] = useState<string | null>(null);

  if (!canView) return null;

  const handleLoad = async () => {
    setIsLoading(true);
    setError(null);
    try {
      setResult(await jobCostingService.getContractProfitability(contract.id, periodStart, periodEnd));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load profitability for this period.'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleAddCost = async () => {
    if (!costSiteId || !costDescription.trim() || !costAmount.trim()) return;
    setIsSavingCost(true);
    setCostError(null);
    try {
      await jobCostingService.addCostEntry(tenantId, contract.id, costSiteId, costCategory, costDescription.trim(), Number(costAmount), costDate);
      setCostDescription('');
      setCostAmount('');
    } catch (err) {
      setCostError(getDbErrorMessage(err, 'Failed to record this cost entry.'));
    } finally {
      setIsSavingCost(false);
    }
  };

  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-base font-semibold text-content-primary">Profitability</h2>
      <p className="text-xs text-content-tertiary">
        Revenue minus Labour, Consumables, Equipment and Other direct costs — every figure is a real aggregate from invoices, attendance, inventory movements and recorded cost entries for this period.
      </p>

      <div className="flex flex-wrap items-end gap-2">
        <TextField label="Period start" type="date" value={periodStart} onChange={(event) => setPeriodStart(event.target.value)} />
        <TextField label="Period end" type="date" value={periodEnd} onChange={(event) => setPeriodEnd(event.target.value)} />
        <Button variant="secondary" onClick={() => void handleLoad()} isLoading={isLoading}>
          Calculate
        </Button>
      </div>

      <ErrorAlert message={error} />

      {result && (
        <dl className="grid grid-cols-2 gap-4 rounded-card border border-border bg-surface-raised p-4 sm:grid-cols-4">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Revenue</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(result.revenue)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Labour</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(result.labourCost)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Consumables</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(result.consumablesCost)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Equipment</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(result.equipmentCost)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Other</dt>
            <dd className="mt-1 text-sm text-content-primary">{formatCurrency(result.otherCost)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Gross Contribution</dt>
            <dd className="mt-1 text-base font-semibold text-content-primary">{formatCurrency(result.grossContribution)}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Gross Margin</dt>
            <dd className="mt-1 text-base font-semibold text-content-primary">{result.grossMarginPct !== null ? `${result.grossMarginPct}%` : 'n/a — no revenue in period'}</dd>
          </div>
        </dl>
      )}

      <div className="flex flex-col gap-2 rounded-card border border-dashed border-border-strong bg-surface-raised p-4">
        <h3 className="text-sm font-semibold text-content-primary">Record a direct cost</h3>
        <p className="text-xs text-content-tertiary">Labour and consumables are computed automatically from attendance and inventory records — only equipment/other direct costs (rental, subcontractor, waste) are entered manually here.</p>
        <ErrorAlert message={costError} />
        <div className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-sm">
            Site
            <select value={costSiteId} onChange={(event) => setCostSiteId(event.target.value)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
              <option value="">Select a site…</option>
              {coveredSites.map((site) => (
                <option key={site.id} value={site.id}>
                  {site.name}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Category
            <select value={costCategory} onChange={(event) => setCostCategory(event.target.value as 'equipment' | 'other')} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
              <option value="equipment">Equipment</option>
              <option value="other">Other</option>
            </select>
          </label>
          <TextField label="Description" value={costDescription} onChange={(event) => setCostDescription(event.target.value)} />
          <TextField label="Amount (ZAR)" type="number" min={0} step="0.01" value={costAmount} onChange={(event) => setCostAmount(event.target.value)} />
          <TextField label="Date" type="date" value={costDate} onChange={(event) => setCostDate(event.target.value)} />
          <Button variant="secondary" onClick={() => void handleAddCost()} isLoading={isSavingCost} disabled={!costSiteId || !costDescription.trim() || !costAmount.trim()}>
            Record cost
          </Button>
        </div>
      </div>
    </section>
  );
}
