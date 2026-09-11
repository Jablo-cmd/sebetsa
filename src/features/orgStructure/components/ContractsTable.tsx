import { Link } from 'react-router-dom';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { cn } from '@/lib/cn';
import type { Contract, Client } from '@/features/orgStructure/types/orgStructure.types';

export interface ContractsTableProps {
  contracts: Contract[];
  clients: Client[];
}

const STATUS_CLASSES: Record<Contract['status'], string> = {
  draft: 'text-content-tertiary',
  active: 'text-success-500',
  expired: 'text-warning-600 dark:text-warning-500',
  terminated: 'text-danger-600',
};

export function ContractsTable({ contracts, clients }: ContractsTableProps) {
  if (contracts.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        No contracts match your filters.
      </div>
    );
  }

  const clientName = (clientId: string) => clients.find((c) => c.id === clientId)?.name ?? '—';

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[720px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            <th scope="col" className="px-4 py-3 font-medium">
              Contract #
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Client
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Start
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              End
            </th>
            <th scope="col" className="px-4 py-3 font-medium">
              Status
            </th>
          </tr>
        </thead>
        <tbody>
          {contracts.map((contract) => (
            <tr key={contract.id} className="border-b border-border last:border-0">
              <td className="px-4 py-3 font-medium text-content-primary">
                <Link to={`/contracts/${contract.id}`} className="focus-ring rounded hover:text-brand-600">
                  {contract.contractNumber}
                </Link>
              </td>
              <td className="px-4 py-3 text-content-secondary">{clientName(contract.clientId)}</td>
              <td className="px-4 py-3 text-content-secondary">{contract.startDate}</td>
              <td className="px-4 py-3 text-content-secondary">{contract.endDate ?? '—'}</td>
              <td className={cn('px-4 py-3 capitalize', STATUS_CLASSES[contract.status])}>{contract.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
