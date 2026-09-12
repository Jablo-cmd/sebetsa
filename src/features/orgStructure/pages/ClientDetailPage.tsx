import { useCallback, useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { usePermissions } from '@/hooks/usePermissions';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { useSitesForClient } from '@/features/orgStructure/hooks/useSites';
import { useContractsForClient } from '@/features/orgStructure/hooks/useContracts';
import { clientContactService, type ClientContact } from '@/features/orgStructure/services/clientContactService';
import { getDbErrorMessage } from '@/lib/dbErrors';

const CONTRACT_STATUS_CLASSES: Record<string, string> = {
  draft: 'text-content-tertiary',
  active: 'text-success-500',
  expiring: 'text-warning-600 dark:text-warning-500',
  suspended: 'text-warning-600 dark:text-warning-500',
  expired: 'text-warning-600 dark:text-warning-500',
  terminated: 'text-danger-600',
};

export function ClientDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const { client, isLoading, error } = useClient(id);
  const { sites, isLoading: sitesLoading } = useSitesForClient(id);
  const { contracts, isLoading: contractsLoading } = useContractsForClient(id);
  const [contacts, setContacts] = useState<ClientContact[]>([]);
  const [contactsError, setContactsError] = useState<string | null>(null);
  const [contactName, setContactName] = useState('');
  const [contactRole, setContactRole] = useState('');
  const [isAddingContact, setIsAddingContact] = useState(false);

  const loadContacts = useCallback(async () => {
    if (!id) return;
    try {
      setContacts(await clientContactService.getContactsForClient(id));
    } catch (err) {
      setContactsError(getDbErrorMessage(err, 'Failed to load contacts.'));
    }
  }, [id]);

  useEffect(() => {
    void loadContacts();
  }, [loadContacts]);

  const handleAddContact = async () => {
    if (!id || !client || !contactName.trim()) return;
    setIsAddingContact(true);
    setContactsError(null);
    try {
      await clientContactService.createContact({ tenantId: client.tenantId, clientId: id, name: contactName.trim(), roleTitle: contactRole.trim() || undefined });
      setContactName('');
      setContactRole('');
      void loadContacts();
    } catch (err) {
      setContactsError(getDbErrorMessage(err, 'Failed to add the contact.'));
    } finally {
      setIsAddingContact(false);
    }
  };

  if (isLoading) {
    return <FullScreenSpinner label="Loading client…" />;
  }

  if (error) {
    return <FullScreenNotice title="Something went wrong" message={error} />;
  }

  if (!client) {
    return (
      <FullScreenNotice
        title="Client not found"
        message="This client doesn't exist, or you don't have access to view it."
        action={
          <Link to="/clients" className="focus-ring rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Clients
          </Link>
        }
      />
    );
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button
        type="button"
        onClick={() => navigate('/clients')}
        className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary"
      >
        ← Back to Clients
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{client.name}</h1>
            <p className="text-sm text-content-secondary">{client.industry ?? 'No industry on file'}</p>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium capitalize text-brand-700 dark:bg-brand-500/15 dark:text-brand-200">
            {client.status}
          </span>
        </div>

        <dl className="mt-6 grid grid-cols-1 gap-4 border-t border-border pt-5 sm:grid-cols-2">
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Primary contact</dt>
            <dd className="mt-1 text-sm text-content-primary">{client.primaryContactName ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Contact email</dt>
            <dd className="mt-1 text-sm text-content-primary">{client.primaryContactEmail ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium uppercase tracking-wide text-content-tertiary">Contact phone</dt>
            <dd className="mt-1 text-sm text-content-primary">{client.primaryContactPhone ?? '—'}</dd>
          </div>
        </dl>
      </div>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Contacts</h2>
        {contactsError && <p className="text-sm font-medium text-danger-600">{contactsError}</p>}
        {contacts.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No named contacts for this client yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {contacts.map((contact) => (
              <div key={contact.id} className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
                <div>
                  <p className="font-medium text-content-primary">{contact.name}</p>
                  <p className="text-xs text-content-tertiary">{contact.roleTitle ?? '—'} {contact.email ? `· ${contact.email}` : ''}</p>
                </div>
              </div>
            ))}
          </div>
        )}
        {canManage && (
          <div className="flex flex-wrap items-end gap-2">
            <TextField label="Name" placeholder="Jane Ops" value={contactName} onChange={(event) => setContactName(event.target.value)} />
            <TextField label="Role" placeholder="Operations Lead" value={contactRole} onChange={(event) => setContactRole(event.target.value)} />
            <Button variant="secondary" onClick={() => void handleAddContact()} isLoading={isAddingContact} disabled={!contactName.trim()}>
              Add contact
            </Button>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Sites</h2>
          <Link to="/sites" className="focus-ring rounded text-xs font-medium text-brand-600 hover:underline">
            Manage sites
          </Link>
        </div>
        {sitesLoading ? (
          <p className="text-sm text-content-tertiary">Loading sites…</p>
        ) : sites.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No sites for this client yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {sites.map((site) => (
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
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold text-content-primary">Contracts</h2>
          <Link to="/contracts" className="focus-ring rounded text-xs font-medium text-brand-600 hover:underline">
            Manage contracts
          </Link>
        </div>
        {contractsLoading ? (
          <p className="text-sm text-content-tertiary">Loading contracts…</p>
        ) : contracts.length === 0 ? (
          <p className="rounded-card border border-border bg-surface-raised px-4 py-8 text-center text-sm text-content-tertiary">
            No contracts for this client yet.
          </p>
        ) : (
          <div className="flex flex-col divide-y divide-border rounded-card border border-border bg-surface-raised">
            {contracts.map((contract) => (
              <Link
                key={contract.id}
                to={`/contracts/${contract.id}`}
                className="focus-ring flex items-center justify-between gap-3 px-4 py-3 text-sm transition-colors hover:bg-surface-sunken"
              >
                <span className="font-medium text-content-primary">{contract.contractNumber}</span>
                <span className={`text-xs font-medium capitalize ${CONTRACT_STATUS_CLASSES[contract.status] ?? 'text-content-tertiary'}`}>
                  {contract.status}
                </span>
              </Link>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
