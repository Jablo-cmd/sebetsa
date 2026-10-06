import type { ReactNode } from 'react';
import { TableScrollContainer } from '@/components/ui/TableScrollContainer';
import { LoadingBlock } from '@/components/ui/LoadingBlock';
import { cn } from '@/lib/cn';

export interface DataTableColumn<T> {
  key: string;
  header: string;
  render: (row: T) => ReactNode;
  align?: 'left' | 'right';
  className?: string;
}

export interface DataTableProps<T> {
  columns: DataTableColumn<T>[];
  rows: T[];
  getRowKey: (row: T) => string;
  isLoading?: boolean;
  loadingLabel?: string;
  emptyMessage?: string;
  onRowClick?: (row: T) => void;
}

/**
 * A generic table shell (FND-UX-004) — the exact markup shape every
 * hand-rolled `*Table` component in this app already converged on
 * independently (EmployeesTable, SitesTable, ContractsTable,
 * etc.: `TableScrollContainer` + `border-b border-border text-xs uppercase
 * tracking-wide` header + `border-b border-border last:border-0` rows +
 * `px-4 py-3` cells), extracted so a NEW table doesn't have to re-derive
 * that shape from scratch. Deliberately does not migrate any of those
 * existing, already-tested tables — each already works, and rewriting a
 * dozen working, tested components to shave duplication with no reported
 * defect is exactly the kind of unprompted rebuild this codebase's own
 * standing instruction warns against. This is for tables built from here
 * on.
 */
export function DataTable<T>({
  columns,
  rows,
  getRowKey,
  isLoading = false,
  loadingLabel = 'Loading…',
  emptyMessage = 'No records found.',
  onRowClick,
}: DataTableProps<T>) {
  if (isLoading) {
    return (
      <div className="rounded-card border border-border bg-surface-raised">
        <LoadingBlock label={loadingLabel} />
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className="rounded-card border border-border bg-surface-raised px-4 py-10 text-center text-sm text-content-tertiary">
        {emptyMessage}
      </div>
    );
  }

  return (
    <TableScrollContainer>
      <table className="w-full min-w-[640px] text-left text-sm">
        <thead>
          <tr className="border-b border-border text-xs uppercase tracking-wide text-content-tertiary">
            {columns.map((column) => (
              <th
                key={column.key}
                scope="col"
                className={cn('px-4 py-3 font-medium', column.align === 'right' && 'text-right')}
              >
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr
              key={getRowKey(row)}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              className={cn('border-b border-border last:border-0', onRowClick && 'cursor-pointer hover:bg-surface-sunken')}
            >
              {columns.map((column) => (
                <td key={column.key} className={cn('px-4 py-3 text-content-secondary', column.align === 'right' && 'text-right', column.className)}>
                  {column.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </TableScrollContainer>
  );
}
