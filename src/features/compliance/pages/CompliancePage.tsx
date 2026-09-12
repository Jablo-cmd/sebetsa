import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { complianceService } from '@/features/compliance/services/complianceService';
import type { ComplianceRecord, ComplianceRequirement } from '@/features/compliance/types/compliance.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_CLASSES: Record<string, string> = {
  pending: 'bg-surface-sunken text-content-secondary',
  in_progress: 'bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-200',
  compliant: 'bg-success-50 text-success-700 dark:bg-success-500/15 dark:text-success-200',
  non_compliant: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
  expired: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
  waived: 'bg-surface-sunken text-content-tertiary',
};

/** Compliance requirement catalogue (tenant-configurable) and the tracked
 * record instances against it. Gated by compliance.manage — an operational
 * management function, not a self-service one. */
export function CompliancePage() {
  const organization = useCurrentOrganization();
  const [requirements, setRequirements] = useState<ComplianceRequirement[]>([]);
  const [records, setRecords] = useState<ComplianceRecord[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [newRequirementName, setNewRequirementName] = useState('');
  const [newRequirementCategory, setNewRequirementCategory] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      const [reqs, recs] = await Promise.all([
        complianceService.getRequirements(organization.id),
        complianceService.getRecords(organization.id),
      ]);
      setRequirements(reqs);
      setRecords(recs);
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load compliance data.'));
    } finally {
      setIsLoading(false);
    }
  }, [organization]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!organization) return <NoActiveOrganizationNotice resource="compliance" />;

  const handleCreateRequirement = async () => {
    if (!newRequirementName.trim() || !newRequirementCategory.trim()) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await complianceService.createRequirement({
        tenantId: organization.id,
        name: newRequirementName.trim(),
        category: newRequirementCategory.trim(),
        appliesToScope: 'site',
      });
      setNewRequirementName('');
      setNewRequirementCategory('');
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to create the compliance requirement.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleVerify = async (recordId: string, approve: boolean) => {
    setError(null);
    try {
      await complianceService.verifyRecord(recordId, approve);
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to verify the compliance record.'));
    }
  };

  const handleTrack = async (requirementId: string) => {
    setError(null);
    try {
      const dueDate = new Date();
      dueDate.setDate(dueDate.getDate() + 30);
      await complianceService.upsertRecord({ requirementId, dueDate: dueDate.toISOString().slice(0, 10) });
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to start tracking this requirement.'));
    }
  };

  const requirementName = (requirementId: string) => requirements.find((r) => r.id === requirementId)?.name ?? requirementId;

  return (
    <PageContainer>
      <PageHeader title="Compliance" description="Tenant-configurable compliance requirements and tracked records." />

      <ErrorAlert message={error} />

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <p className="text-sm font-medium text-content-primary">Add a requirement</p>
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <TextField label="Name" placeholder="e.g. Fire Safety Certificate" value={newRequirementName} onChange={(event) => setNewRequirementName(event.target.value)} />
          <TextField label="Category" placeholder="e.g. safety" value={newRequirementCategory} onChange={(event) => setNewRequirementCategory(event.target.value)} />
          <Button onClick={() => void handleCreateRequirement()} isLoading={isSubmitting} disabled={!newRequirementName.trim() || !newRequirementCategory.trim()}>
            Add
          </Button>
        </div>
      </div>

      {requirements.length > 0 && (
        <div className="mt-4 flex flex-col gap-2">
          <p className="text-sm font-medium text-content-primary">Requirements</p>
          {requirements.map((requirement) => (
            <div key={requirement.id} className="flex items-center justify-between rounded-xl border border-border bg-surface-raised p-4">
              <div>
                <p className="text-sm font-medium text-content-primary">{requirement.name}</p>
                <p className="text-xs text-content-tertiary">{requirement.category} · {requirement.appliesToScope}</p>
              </div>
              <Button variant="secondary" onClick={() => void handleTrack(requirement.id)}>
                Start tracking
              </Button>
            </div>
          ))}
        </div>
      )}

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : records.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No compliance records tracked yet.</p>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-border text-xs uppercase text-content-secondary">
                <th className="px-3 py-2">Requirement</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Due</th>
                <th className="px-3 py-2">Expiry</th>
                <th className="px-3 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {records.map((record) => (
                <tr key={record.id} className="border-b border-border last:border-0">
                  <td className="px-3 py-2.5">{requirementName(record.requirementId)}</td>
                  <td className="px-3 py-2.5">
                    <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_CLASSES[record.status] ?? ''}`}>{record.status}</span>
                  </td>
                  <td className="px-3 py-2.5">{record.dueDate ? new Date(record.dueDate).toLocaleDateString() : '—'}</td>
                  <td className="px-3 py-2.5">{record.expiryDate ? new Date(record.expiryDate).toLocaleDateString() : '—'}</td>
                  <td className="px-3 py-2.5 text-right">
                    {record.status !== 'compliant' && (
                      <>
                        <Button variant="ghost" onClick={() => void handleVerify(record.id, true)}>Approve</Button>
                        <Button variant="ghost" onClick={() => void handleVerify(record.id, false)}>Reject</Button>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </PageContainer>
  );
}
