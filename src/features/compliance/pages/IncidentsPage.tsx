import { useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAuth } from '@/features/auth/context/authContext';
import { hasPermission } from '@/features/rbac';
import { useIncidents } from '@/features/compliance/hooks/useIncidents';
import { IncidentDetailModal } from '@/features/compliance/components/IncidentDetailModal';
import { incidentService } from '@/features/compliance/services/incidentService';
import { INCIDENT_CATEGORY_LABELS, INCIDENT_SEVERITY_LABELS, INCIDENT_STATUS_LABELS } from '@/features/compliance/types/compliance.types';
import type { IncidentCategoryEnum, IncidentSeverityEnum } from '@/lib/dbTypes';
import { getDbErrorMessage } from '@/lib/dbErrors';

const SEVERITY_CLASSES: Record<string, string> = {
  low: 'bg-surface-sunken text-content-secondary',
  medium: 'bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-200',
  high: 'bg-warning-50 text-warning-700 dark:bg-warning-500/15 dark:text-warning-200',
  critical: 'bg-danger-50 text-danger-700 dark:bg-danger-500/15 dark:text-danger-200',
};

/** Incident register: any employee can report; can_manage_operations() tier
 * drives the lifecycle. Reporting is intentionally not gated behind a
 * separate permission — everyone who can reach the page can report an
 * incident, matching the RPC's own self-service authorization. */
export function IncidentsPage() {
  const organization = useCurrentOrganization();
  const { user } = useAuth();
  const canManage = hasPermission(user?.role ?? null, 'incident.manage');
  const { incidents, isLoading, error, refetch } = useIncidents(organization?.id);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  // Derived from the live list (not a copied snapshot) so a status
  // transition inside the modal is reflected immediately once refetch()
  // resolves, instead of the modal showing stale pre-transition data.
  const selected = incidents.find((incident) => incident.id === selectedId) ?? null;
  const [isReporting, setIsReporting] = useState(false);
  const [reportError, setReportError] = useState<string | null>(null);
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<IncidentCategoryEnum>('operational_other');
  const [severity, setSeverity] = useState<IncidentSeverityEnum>('low');

  if (!organization) return <NoActiveOrganizationNotice resource="incidents" />;

  const handleReport = async () => {
    if (!description.trim()) return;
    setIsReporting(true);
    setReportError(null);
    try {
      await incidentService.reportIncident({
        tenantId: organization.id,
        category,
        severity,
        occurredAt: new Date().toISOString(),
        description: description.trim(),
      });
      setDescription('');
      void refetch();
    } catch (err) {
      setReportError(getDbErrorMessage(err, 'Failed to report the incident.'));
    } finally {
      setIsReporting(false);
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Incidents" description="Workplace, safety and operational incident register." />

      <ErrorAlert message={error} />

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <p className="text-sm font-medium text-content-primary">Report an incident</p>
        {reportError && <p className="mt-1 text-sm font-medium text-danger-600">{reportError}</p>}
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-sm">
            Category
            <select value={category} onChange={(event) => setCategory(event.target.value as IncidentCategoryEnum)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
              {Object.entries(INCIDENT_CATEGORY_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-sm">
            Severity
            <select value={severity} onChange={(event) => setSeverity(event.target.value as IncidentSeverityEnum)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
              {Object.entries(INCIDENT_SEVERITY_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </label>
          <TextField label="Description" placeholder="What happened?" value={description} onChange={(event) => setDescription(event.target.value)} />
          <Button onClick={() => void handleReport()} isLoading={isReporting} disabled={!description.trim()}>
            Report
          </Button>
        </div>
      </div>

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : incidents.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No incidents reported.</p>
      ) : (
        <div className="mt-4 flex flex-col gap-2">
          {incidents.map((incident) => (
            <button
              key={incident.id}
              type="button"
              onClick={() => setSelectedId(incident.id)}
              className="focus-ring flex items-center justify-between rounded-xl border border-border bg-surface-raised p-4 text-left hover:bg-surface-sunken"
            >
              <div>
                <p className="text-sm font-medium text-content-primary">{incident.referenceNumber} — {INCIDENT_CATEGORY_LABELS[incident.category]}</p>
                <p className="text-xs text-content-tertiary">{new Date(incident.occurredAt).toLocaleString()} · {INCIDENT_STATUS_LABELS[incident.status]}</p>
              </div>
              <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium ${SEVERITY_CLASSES[incident.severity] ?? ''}`}>
                {INCIDENT_SEVERITY_LABELS[incident.severity]}
              </span>
            </button>
          ))}
        </div>
      )}

      <IncidentDetailModal
        isOpen={selected !== null}
        onClose={() => setSelectedId(null)}
        incident={selected}
        canManage={canManage}
        onChanged={() => void refetch()}
      />
    </PageContainer>
  );
}
