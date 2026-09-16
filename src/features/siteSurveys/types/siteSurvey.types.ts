import type { Database } from '@/lib/database.types';

export type SiteSurveyStatus = Database['public']['Enums']['site_survey_status'];

export interface SiteSurvey {
  id: string;
  tenantId: string;
  clientId: string;
  siteId: string | null;
  conductedBy: string | null;
  status: SiteSurveyStatus;
  prospectiveSiteName: string;
  address: string | null;
  buildingType: string | null;
  floorCount: number | null;
  approxAreaSqm: number | null;
  officeCount: number | null;
  bathroomCount: number | null;
  kitchenCount: number | null;
  entranceCount: number | null;
  commonAreaCount: number | null;
  windowCount: number | null;
  floorTypes: string | null;
  specialSurfaces: string | null;
  operatingHours: string | null;
  accessRestrictions: string | null;
  requiredServices: string | null;
  equipmentRequirements: string | null;
  consumableRequirements: string | null;
  risks: string | null;
  specialInstructions: string | null;
  notes: string | null;
  conductedAt: string;
  createdAt: string;
  updatedAt: string;
}

export interface CreateSiteSurveyInput {
  clientId: string;
  prospectiveSiteName: string;
  address?: string | null;
  buildingType?: string | null;
  floorCount?: number | null;
  approxAreaSqm?: number | null;
  officeCount?: number | null;
  bathroomCount?: number | null;
  kitchenCount?: number | null;
  entranceCount?: number | null;
  commonAreaCount?: number | null;
  windowCount?: number | null;
  floorTypes?: string | null;
  specialSurfaces?: string | null;
  operatingHours?: string | null;
  accessRestrictions?: string | null;
  requiredServices?: string | null;
  equipmentRequirements?: string | null;
  consumableRequirements?: string | null;
  risks?: string | null;
  specialInstructions?: string | null;
  notes?: string | null;
}

export type UpdateSiteSurveyInput = Partial<Omit<CreateSiteSurveyInput, 'clientId'>> & { status?: SiteSurveyStatus };

export interface SiteSurveysListFilters {
  clientId?: string;
  status?: SiteSurveyStatus;
}

export interface SiteSurveysListPage {
  surveys: SiteSurvey[];
  totalCount: number;
  page: number;
  pageSize: number;
}
