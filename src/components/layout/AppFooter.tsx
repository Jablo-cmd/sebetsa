export function AppFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="flex h-9 shrink-0 items-center justify-between gap-4 border-t border-border bg-surface-raised px-4 text-xs text-content-secondary sm:px-6">
      <span className="truncate">SEBETSA · Workforce Operations Platform</span>
      <span className="shrink-0 truncate">© {year} Sebetsa</span>
    </footer>
  );
}
