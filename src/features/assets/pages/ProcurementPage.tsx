import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { useSitesList } from '@/features/attendance/hooks/useSitesList';
import { useCurrentOrganization } from '@/features/tenant/hooks/useCurrentOrganization';
import { useAuth } from '@/features/auth/context/authContext';
import { hasPermission } from '@/features/rbac';
import { procurementService } from '@/features/assets/services/procurementService';
import { PROCUREMENT_STATUS_LABELS } from '@/features/assets/types/assets.types';
import type { ProcurementRequest } from '@/features/assets/types/assets.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const NEXT_STEP: Partial<Record<ProcurementRequest['status'], ProcurementRequest['status']>> = {
  approved: 'ordered',
  ordered: 'received',
  received: 'completed',
};

/** Procurement requests: any employee can request; can_manage_operations()
 * tier decides and advances. Not accounts payable — no invoicing/payment. */
export function ProcurementPage() {
  const organization = useCurrentOrganization();
  const { user } = useAuth();
  const canManage = hasPermission(user?.role ?? null, 'procurement.manage');
  const [requests, setRequests] = useState<ProcurementRequest[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [description, setDescription] = useState('');
  const [quantity, setQuantity] = useState('1');
  const [estimatedCost, setEstimatedCost] = useState('');
  const [siteId, setSiteId] = useState('');
  const { sites } = useSitesList(organization?.id);
  const [rejectionReasons, setRejectionReasons] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  const load = useCallback(async () => {
    if (!organization) return;
    setIsLoading(true);
    setError(null);
    try {
      setRequests(await procurementService.getRequests(organization.id));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load procurement requests.'));
    } finally {
      setIsLoading(false);
    }
  }, [organization]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!organization) return <NoActiveOrganizationNotice resource="procurement" />;

  const handleSubmit = async () => {
    const parsedQuantity = Number(quantity);
    if (!description.trim()) return;
    if (!Number.isFinite(parsedQuantity) || parsedQuantity <= 0) {
      setError('Enter a quantity greater than zero.');
      return;
    }
    const parsedCost = estimatedCost.trim() === '' ? undefined : Number(estimatedCost);
    if (parsedCost !== undefined && (!Number.isFinite(parsedCost) || parsedCost < 0)) {
      setError('The estimated cost must be zero or more.');
      return;
    }
    setIsSubmitting(true);
    setError(null);
    try {
      await procurementService.submitRequest({
        tenantId: organization.id,
        itemDescription: description.trim(),
        quantity: parsedQuantity,
        siteId: siteId || undefined,
        estimatedCost: parsedCost,
      });
      setDescription('');
      setQuantity('1');
      setEstimatedCost('');
      setSiteId('');
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to submit the procurement request.'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDecide = async (id: string, approve: boolean) => {
    setError(null);
    try {
      await procurementService.decideRequest(id, approve, approve ? undefined : rejectionReasons[id]?.trim());
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to decide on the procurement request.'));
    }
  };

  const handleAdvance = async (id: string, status: ProcurementRequest['status']) => {
    setError(null);
    try {
      await procurementService.advanceRequest(id, status);
      void load();
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to advance the procurement request.'));
    }
  };

  return (
    <PageContainer>
      <PageHeader title="Procurement" description="Operational procurement requests — not accounts payable or invoicing." />

      <ErrorAlert message={error} />

      <div className="mt-4 rounded-xl border border-border bg-surface-raised p-4">
        <p className="text-sm font-medium text-content-primary">Request an item</p>
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <TextField label="Description" placeholder="Replacement mop heads" value={description} onChange={(event) => setDescription(event.target.value)} />
          <TextField label="Quantity" type="number" value={quantity} onChange={(event) => setQuantity(event.target.value)} />
          <TextField label="Estimated cost (R)" type="number" min={0} placeholder="optional" value={estimatedCost} onChange={(event) => setEstimatedCost(event.target.value)} />
          <label className="flex flex-col gap-1 text-sm">
            Site
            <select value={siteId} onChange={(event) => setSiteId(event.target.value)} className="focus-ring h-11 rounded-lg border border-border-strong bg-surface-raised px-3">
              <option value="">No specific site</option>
              {sites.map((site) => (
                <option key={site.id} value={site.id}>{site.name}</option>
              ))}
            </select>
          </label>
          <Button onClick={() => void handleSubmit()} isLoading={isSubmitting} disabled={!description.trim()}>
            Submit
          </Button>
        </div>
      </div>

      {isLoading ? (
        <p className="mt-6 text-sm text-content-secondary">Loading…</p>
      ) : requests.length === 0 ? (
        <p className="mt-6 text-sm text-content-secondary">No procurement requests yet.</p>
      ) : (
        <div className="mt-4 flex flex-col gap-2">
          {requests.map((request) => {
            const nextStep = NEXT_STEP[request.status];
            return (
              <div key={request.id} className="flex items-center justify-between rounded-xl border border-border bg-surface-raised p-4">
                <div>
                  <p className="text-sm font-medium text-content-primary">{request.itemDescription} × {request.quantity}</p>
                  <p className="text-xs text-content-tertiary">
                    {PROCUREMENT_STATUS_LABELS[request.status]}
                    {request.siteId ? ` · ${sites.find((site) => site.id === request.siteId)?.name ?? 'Site'}` : ''}
                    {request.estimatedCost !== null ? ` · est. R${request.estimatedCost}` : ''}
                  </p>
                  {request.status === 'rejected' && request.rejectedReason && (
                    <p className="text-xs text-danger-600">Reason: {request.rejectedReason}</p>
                  )}
                </div>
                {canManage && (
                  <div className="flex gap-2">
                    {request.status === 'submitted' && (
                      <>
                        <input
                          type="text"
                          placeholder="Reason if rejecting"
                          aria-label={`Rejection reason for ${request.itemDescription}`}
                          value={rejectionReasons[request.id] ?? ''}
                          onChange={(event) => setRejectionReasons((prev) => ({ ...prev, [request.id]: event.target.value }))}
                          className="focus-ring h-9 w-44 rounded-lg border border-border-strong bg-surface-raised px-2 text-sm"
                        />
                        <Button variant="ghost" onClick={() => void handleDecide(request.id, true)}>Approve</Button>
                        <Button variant="ghost" onClick={() => void handleDecide(request.id, false)} disabled={!rejectionReasons[request.id]?.trim()}>Reject</Button>
                      </>
                    )}
                    {nextStep && (
                      <Button variant="ghost" onClick={() => void handleAdvance(request.id, nextStep)}>Mark {PROCUREMENT_STATUS_LABELS[nextStep]}</Button>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </PageContainer>
  );
}
