import { useCallback, useEffect, useState } from 'react';
import { PageContainer } from '@/components/ui/PageContainer';
import { PageHeader } from '@/components/ui/PageHeader';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { NoActiveOrganizationNotice } from '@/components/ui/NoActiveOrganizationNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
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
    if (!description.trim() || !parsedQuantity || parsedQuantity <= 0) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await procurementService.submitRequest({ tenantId: organization.id, itemDescription: description.trim(), quantity: parsedQuantity });
      setDescription('');
      setQuantity('1');
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
      await procurementService.decideRequest(id, approve);
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
                  <p className="text-xs text-content-tertiary">{PROCUREMENT_STATUS_LABELS[request.status]}</p>
                </div>
                {canManage && (
                  <div className="flex gap-2">
                    {request.status === 'submitted' && (
                      <>
                        <Button variant="ghost" onClick={() => void handleDecide(request.id, true)}>Approve</Button>
                        <Button variant="ghost" onClick={() => void handleDecide(request.id, false)}>Reject</Button>
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
