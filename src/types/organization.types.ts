/** Mirrors the `organization_status` Postgres enum (see supabase/migrations). */
export type OrganizationStatus = 'pending' | 'active' | 'inactive' | 'suspended';

/** A tenant root — one row per client organization onboarded onto Sebetsa. */
export interface Organization {
  id: string;
  name: string;
  registrationNumber: string | null;
  industry: string | null;
  email: string | null;
  phone: string | null;
  website: string | null;
  logoUrl: string | null;
  address: string | null;
  timezone: string;
  currency: string;
  language: string;
  status: OrganizationStatus;
  createdAt: string;
  updatedAt: string;
}
