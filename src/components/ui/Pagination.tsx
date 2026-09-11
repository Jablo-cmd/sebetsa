import { Button } from '@/components/ui/Button';

export interface PaginationProps {
  page: number;
  pageSize: number;
  totalCount: number;
  onPageChange: (page: number) => void;
  /** Lower-case plural noun for the "no ___" empty state, e.g. "employees", "clients". */
  resource: string;
}

export function Pagination({ page, pageSize, totalCount, onPageChange, resource }: PaginationProps) {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  const from = totalCount === 0 ? 0 : (page - 1) * pageSize + 1;
  const to = Math.min(page * pageSize, totalCount);

  return (
    <div className="flex flex-col items-center justify-between gap-3 sm:flex-row">
      <p className="text-sm text-content-tertiary">
        {totalCount === 0 ? `No ${resource}` : `Showing ${from}–${to} of ${totalCount}`}
      </p>
      <div className="flex gap-2">
        <div className="w-24">
          <Button type="button" variant="secondary" disabled={page <= 1} onClick={() => onPageChange(page - 1)}>
            Previous
          </Button>
        </div>
        <div className="w-20">
          <Button
            type="button"
            variant="secondary"
            disabled={page >= totalPages}
            onClick={() => onPageChange(page + 1)}
          >
            Next
          </Button>
        </div>
      </div>
    </div>
  );
}
