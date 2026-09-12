import { useCallback, useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { usePermissions } from '@/hooks/usePermissions';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useContract } from '@/features/orgStructure/hooks/useContracts';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useContractSiteIds } from '@/features/orgStructure/hooks/useContracts';
import { useAllClients } from '@/features/orgStructure/hooks/useClients';
import { useAllSites } from '@/features/orgStructure/hooks/useSites';
import { contractService } from '@/features/orgStructure/services/contractService';
import { ContractFormModal } from '@/features/orgStructure/components/ContractFormModal';
import { slaService, type SlaDefinition, type SlaMeasurement } from '@/features/orgStructure/services/slaService';
import { contractDocumentService, type ContractDocument } from '@/features/orgStructure/services/contractDocumentService';
import type { ContractStatus } from '@/features/orgStructure/types/orgStructure.types';
import type { SlaMetricTypeEnum } from '@/lib/dbTypes';
import { getDbErrorMessage } from '@/lib/dbErrors';

const METRIC_LABELS: Record<SlaMetricTypeEnum, string> = {
  staffing_fulfillment: 'Staffing fulfilment (%)',
  task_completion_rate: 'Task completion rate (%)',
  incident_response_hours: 'Incident response time (hrs)',
  compliance_completion_rate: 'Compliance completion rate (%)',
};

const STATUS_OPTIONS: { value: ContractStatus; label: string }[] = [
  { value: 'draft', label: 'Draft' },
  { value: 'active', label: 'Active' },
  { value: 'expiring', label: 'Expiring' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'expired', label: 'Expired' },
  { value: 'terminated', label: 'Terminated' },
];

export function ContractDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const organization = useCurrentOrganization();
  const { contract, isLoading, error, refetch } = useContract(id);
  const { client } = useClient(contract?.clientId);
  const { siteIds } = useContractSiteIds(id);
  const { sites: allSites } = useAllSites(organization?.id);
  const { clients } = useAllClients(organization?.id);

  const [isEditOpen, setIsEditOpen] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);
  const [isChangingStatus, setIsChangingStatus] = useState(false);

  const [slaDefinitions, setSlaDefinitions] = useState<SlaDefinition[]>([]);
  const [measurements, setMeasurements] = useState<Record<string, SlaMeasurement[]>>({});
  const [slaError, setSlaError] = useState<string | null>(null);
  const [slaName, setSlaName] = useState('');
  const [slaMetric, setSlaMetric] = useState<SlaMetricTypeEnum>('task_completion_rate');
  const [slaTarget, setSlaTarget] = useState('90');
  const [isSavingSla, setIsSavingSla] = useState(false);

  const [documents, setDocuments] = useState<ContractDocument[]>([]);
  const [documentsError, setDocumentsError] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  const loadSla = useCallback(async () => {
    if (!id) return;
    try {
      const definitions = await slaService.getDefinitionsForContract(id);
      setSlaDefinitions(definitions);
      const entries = await Promise.all(definitions.map(async (def) => [def.id, await slaService.getMeasurements(def.id)] as const));
      setMeasurements(Object.fromEntries(entries));
    } catch (err) {
      setSlaError(getDbErrorMessage(err, 'Failed to load SLA data.'));
    }
  }, [id]);

  const loadDocuments = useCallback(async () => {
    if (!id) return;
    try {
      setDocuments(await contractDocumentService.getDocuments(id));
    } catch (err) {
      setDocumentsError(getDbErrorMessage(err, 'Failed to load contract documents.'));
    }
  }, [id]);

  useEffect(() => {
    void loadSla();
    void loadDocuments();
  }, [loadSla, loadDocuments]);

  if (isLoading) {
    return <FullScreenSpinner label="Loading contract…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!contract) {
    return (
      <FullScreenNotice
        title="Contract not found"
        message="This contract doesn't exist, or you don't have access to view it."
        action={
          <Link to="/contracts" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Contracts
          </Link>
        }
      />
    );
  }

  const coveredSites = allSites.filter((s) => siteIds.includes(s.id));

  const handleStatusChange = async (status: ContractStatus) => {
    setStatusError(null);
    setIsChangingStatus(true);
    try {
      await contractService.updateContractStatus(contract.id, status);
      await refetch();
    } catch (err) {
      setStatusError(getDbErrorMessage(err, 'Failed to update contract status.'));
    } finally {
      setIsChangingStatus(false);
    }
  };

  const handleCreateSla = async () => {
    if (!organization || !coveredSites[0] || !slaName.trim()) return;
    setIsSavingSla(true);
    setSlaError(null);
    try {
      await slaService.createDefinition({
        tenantId: organization.id,
        contractId: contract.id,
        siteId: coveredSites[0].id,
        name: slaName.trim(),
        metricType: slaMetric,
        targetValue: Number(slaTarget),
        thresholdOperator: slaMetric === 'incident_response_hours' ? 'lte' : 'gte',
      });
      setSlaName('');
      void loadSla();
    } catch (err) {
      setSlaError(getDbErrorMessage(err, 'Failed to create the SLA definition.'));
    } finally {
      setIsSavingSla(false);
    }
  };

  const handleComputeSla = async (definitionId: string) => {
    setSlaError(null);
    try {
      const now = new Date();
      const periodStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
      const periodEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10);
      await slaService.computeMeasurement(definitionId, periodStart, periodEnd);
      void loadSla();
    } catch (err) {
      setSlaError(getDbErrorMessage(err, 'Failed to compute the SLA measurement.'));
    }
  };

  const handleUploadDocument = async (file: File) => {
    setIsUploading(true);
    setDocumentsError(null);
    try {
      await contractDocumentService.uploadDocument(contract.id, file);
      void loadDocuments();
    } catch (err) {
      setDocumentsError(getDbErrorMessage(err, 'Failed to upload the document.'));
    } finally {
      setIsUploading(false);
    }
  };

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/contracts')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Contracts
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{contract.contractNumber}</h1>
            <p className="text-sm text-content-secondary">
              {client ? (
                <Link to={`/clients/${client.id}`} className="text-brand-600 hover:underline">
                  {client.name}
                </Link>
              ) : (
                'No client'
              )}
            </p>
          </div>
          {canManage ? (
            <select
              aria-label="Contract status"
              value={contract.status}
              disabled={isChangingStatus}
              onChange={(event) => void handleStatusChange(event.target.value as ContractStatus)}
              className="focus-ring h-10 rounded-lg border border-border-strong bg-surface-raised px-3 text-sm font-medium capitalize text-content-primary"
            >
              {STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          ) : (
            <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
              {contract.status}
            </span>
          )}
        </div>

        <ErrorAlert message={statusError} />

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Start date</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.startDate}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">End date</dt>
            <dd className="mt-1 text-sm text-content-primary">{contract.endDate ?? '—'}</dd>
          </div>
          <div className="sm:col-span-2">
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">SLA notes</dt>
            <dd className="mt-1 whitespace-pre-wrap text-sm text-content-primary">{contract.slaNotes ?? '—'}</dd>
          </div>
        </dl>

        {canManage && (
          <div className="mt-6 border-t border-border pt-5">
            <div className="w-full sm:w-auto sm:min-w-[8rem]">
              <Button type="button" variant="secondary" onClick={() => setIsEditOpen(true)}>
                Edit details
              </Button>
            </div>
          </div>
        )}
      </div>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Sites covered</h2>
        {coveredSites.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No sites linked to this contract yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {coveredSites.map((site) => (
              <Link
                key={site.id}
                to={`/sites/${site.id}`}
                className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
              >
                <span className="font-medium text-content-primary">{site.name}</span>
                <span className="text-xs capitalize text-content-tertiary">{site.status}</span>
              </Link>
            ))}
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">SLA performance</h2>
        {slaError && <p className="text-sm font-medium text-danger-600">{slaError}</p>}
        {slaDefinitions.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No SLA metrics defined for this contract yet.
          </p>
        ) : (
          <div className="flex flex-col gap-2">
            {slaDefinitions.map((definition) => {
              const latest = measurements[definition.id]?.[0];
              return (
                <div key={definition.id} className="rounded-xl border border-border bg-surface-raised p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-content-primary">{definition.name}</p>
                      <p className="text-xs text-content-tertiary">{METRIC_LABELS[definition.metricType]} — target {definition.thresholdOperator === 'gte' ? '≥' : '≤'} {definition.targetValue}</p>
                    </div>
                    {canManage && (
                      <Button variant="ghost" onClick={() => void handleComputeSla(definition.id)}>Compute this month</Button>
                    )}
                  </div>
                  {latest && (
                    <p className={`mt-2 text-xs font-medium ${latest.targetMet ? 'text-success-600' : 'text-danger-600'}`}>
                      Latest: {latest.measuredValue} ({latest.targetMet ? 'target met' : 'target missed'}) — {latest.periodStart} to {latest.periodEnd}
                    </p>
                  )}
                </div>
              );
            })}
          </div>
        )}
        {canManage && (
          <div className="flex flex-wrap items-end gap-2">
            <TextField label="Metric name" placeholder="Task completion" value={slaName} onChange={(event) => setSlaName(event.target.value)} />
            <label className="flex flex-col gap-1 text-sm">
              Metric type
              <select value={slaMetric} onChange={(event) => setSlaMetric(event.target.value as SlaMetricTypeEnum)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
                {Object.entries(METRIC_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
            </label>
            <TextField label="Target" type="number" value={slaTarget} onChange={(event) => setSlaTarget(event.target.value)} />
            <Button variant="secondary" onClick={() => void handleCreateSla()} isLoading={isSavingSla} disabled={!slaName.trim() || coveredSites.length === 0}>
              Add SLA metric
            </Button>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Documents</h2>
        {documentsError && <p className="text-sm font-medium text-danger-600">{documentsError}</p>}
        {documents.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No documents uploaded for this contract yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {documents.map((doc) => (
              <div key={doc.id} className="flex items-center justify-between px-4 py-3 text-sm">
                <span className="font-medium text-content-primary">{doc.fileName}</span>
                <span className="text-xs text-content-tertiary">v{doc.version}</span>
              </div>
            ))}
          </div>
        )}
        {canManage && (
          <label className="flex flex-col gap-1 text-sm">
            Upload a document (PDF, JPEG, or PNG — max 10MB)
            <input
              type="file"
              accept="application/pdf,image/jpeg,image/png"
              disabled={isUploading}
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file) void handleUploadDocument(file);
                event.target.value = '';
              }}
              className="focus-ring block w-full text-sm text-content-secondary file:mr-3 file:rounded-md file:border-0 file:bg-brand-50 file:px-3 file:py-2 file:text-sm file:font-medium file:text-brand-700"
            />
          </label>
        )}
      </section>

      {organization && (
        <ContractFormModal
          isOpen={isEditOpen}
          onClose={() => setIsEditOpen(false)}
          tenantId={organization.id}
          contract={contract}
          clients={clients}
          sites={allSites}
          onSaved={() => void refetch()}
        />
      )}
    </div>
  );
}
