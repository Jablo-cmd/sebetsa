export interface PageTitleEntry {
  title: string;
  section: string;
}

/**
 * Static route → { title, section } lookup for the application header's
 * title/breadcrumb block. Purely presentational — does not affect routing,
 * permissions, or data. Ordered longest-prefix-first so a child route
 * (e.g. `/employees/departments`) isn't shadowed by its parent (`/employees`).
 */
const PAGE_TITLES: Array<[string, PageTitleEntry]> = [
  ['/dashboard', { title: 'Dashboard', section: 'Overview' }],
  ['/my-profile', { title: 'My Profile', section: 'Administration' }],
  ['/organizations', { title: 'Organizations', section: 'Administration' }],
  ['/users', { title: 'Users & Roles', section: 'Administration' }],
  ['/regions', { title: 'Regions', section: 'Organisation' }],
  ['/clients', { title: 'Clients', section: 'Organisation' }],
  ['/sites', { title: 'Sites', section: 'Organisation' }],
  ['/contracts', { title: 'Contracts', section: 'Organisation' }],
  ['/employees/departments', { title: 'Departments', section: 'Workforce' }],
  ['/employees', { title: 'Employees', section: 'Workforce' }],
  ['/attendance', { title: 'Attendance', section: 'Operations' }],
  ['/notifications/settings', { title: 'Notification Preferences', section: 'Communication' }],
  ['/notifications', { title: 'Notifications', section: 'Communication' }],
];

const DEFAULT_ENTRY: PageTitleEntry = { title: 'Sebetsa', section: 'Overview' };

export function getPageTitle(pathname: string): PageTitleEntry {
  const match = PAGE_TITLES.find(
    ([prefix]) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
  return match ? match[1] : DEFAULT_ENTRY;
}
