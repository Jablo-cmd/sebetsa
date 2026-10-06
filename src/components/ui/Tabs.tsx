export interface TabItem<K extends string> {
  key: K;
  label: string;
}

export interface TabsProps<K extends string> {
  tabs: TabItem<K>[];
  activeTab: K;
  onChange: (key: K) => void;
}

/**
 * Shared tab bar. Generic over the tab-key union so each caller keeps its
 * own exhaustively-checked `TabKey` type; this component only needs to
 * know it's a string.
 *
 * Deliberately keeps the original `aria-current="page"` semantics rather
 * than introducing a full `role="tab"`/`role="tabpanel"` ARIA pattern —
 * that would be a real accessibility change, not a pure extraction, and
 * belongs in its own reviewed pass rather than riding along with a
 * refactor.
 */
export function Tabs<K extends string>({ tabs, activeTab, onChange }: TabsProps<K>) {
  return (
    <div className="flex flex-wrap gap-1 border-b border-border">
      {tabs.map((tab) => (
        <button
          key={tab.key}
          type="button"
          onClick={() => onChange(tab.key)}
          aria-current={activeTab === tab.key ? 'page' : undefined}
          className={`focus-ring rounded-t-lg px-3.5 py-2.5 text-sm font-medium transition-colors ${
            activeTab === tab.key
              ? 'border-b-2 border-brand-600 text-brand-700 dark:text-brand-300'
              : 'text-content-secondary hover:text-content-primary'
          }`}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}
