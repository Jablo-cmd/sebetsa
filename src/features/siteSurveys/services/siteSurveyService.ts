import { supabase } from '@/lib/supabase';
import type { SiteSurveyRow, SiteSurveyInsert, SiteSurveyUpdate, SiteRow } from '@/lib/dbTypes';
import type {
  SiteSurvey,
  CreateSiteSurveyInput,
  UpdateSiteSurveyInput,
  SiteSurveysListFilters,
  SiteSurveysListPage,
} from '@/features/siteSurveys/types/siteSurvey.types';
import { toSite } from '@/features/orgStructure/services/siteService';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';

const DEFAULT_PAGE_SIZE = 20;

export function toSiteSurvey(row: SiteSurveyRow): SiteSurvey {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    clientId: row.client_id,
    siteId: row.site_id,
    conductedBy: row.conducted_by,
    status: row.status,
    prospectiveSiteName: row.prospective_site_name,
    address: row.address,
    buildingType: row.building_type,
    floorCount: row.floor_count,
    approxAreaSqm: row.approx_area_sqm,
    officeCount: row.office_count,
    bathroomCount: row.bathroom_count,
    kitchenCount: row.kitchen_count,
    entranceCount: row.entrance_count,
    commonAreaCount: row.common_area_count,
    windowCount: row.window_count,
    floorTypes: row.floor_types,
    specialSurfaces: row.special_surfaces,
    operatingHours: row.operating_hours,
    accessRestrictions: row.access_restrictions,
    requiredServices: row.required_services,
    equipmentRequirements: row.equipment_requirements,
    consumableRequirements: row.consumable_requirements,
    risks: row.risks,
    specialInstructions: row.special_instructions,
    notes: row.notes,
    conductedAt: row.conducted_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getSurveys(
  tenantId: string,
  filters: SiteSurveysListFilters = {},
  page = 1,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<SiteSurveysListPage> {
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase.from('site_surveys').select('*', { count: 'exact' }).eq('tenant_id', tenantId);
  if (filters.clientId) query = query.eq('client_id', filters.clientId);
  if (filters.status) query = query.eq('status', filters.status);

  const { data, error, count } = await query.order('conducted_at', { ascending: false }).range(from, to);
  if (error) throw error;

  return { surveys: data.map(toSiteSurvey), totalCount: count ?? 0, page, pageSize };
}

async function getSurvey(id: string): Promise<SiteSurvey | null> {
  const { data, error } = await supabase.from('site_surveys').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return data ? toSiteSurvey(data) : null;
}

function toInsertPayload(tenantId: string, input: CreateSiteSurveyInput): SiteSurveyInsert {
  return {
    tenant_id: tenantId,
    client_id: input.clientId,
    prospective_site_name: input.prospectiveSiteName,
    address: input.address ?? null,
    building_type: input.buildingType ?? null,
    floor_count: input.floorCount ?? null,
    approx_area_sqm: input.approxAreaSqm ?? null,
    office_count: input.officeCount ?? null,
    bathroom_count: input.bathroomCount ?? null,
    kitchen_count: input.kitchenCount ?? null,
    entrance_count: input.entranceCount ?? null,
    common_area_count: input.commonAreaCount ?? null,
    window_count: input.windowCount ?? null,
    floor_types: input.floorTypes ?? null,
    special_surfaces: input.specialSurfaces ?? null,
    operating_hours: input.operatingHours ?? null,
    access_restrictions: input.accessRestrictions ?? null,
    required_services: input.requiredServices ?? null,
    equipment_requirements: input.equipmentRequirements ?? null,
    consumable_requirements: input.consumableRequirements ?? null,
    risks: input.risks ?? null,
    special_instructions: input.specialInstructions ?? null,
    notes: input.notes ?? null,
  };
}

async function createSurvey(tenantId: string, input: CreateSiteSurveyInput): Promise<SiteSurvey> {
  const { data, error } = await supabase.from('site_surveys').insert(toInsertPayload(tenantId, input)).select('*').single();
  if (error) throw error;
  return toSiteSurvey(data);
}

async function updateSurvey(id: string, updates: UpdateSiteSurveyInput): Promise<SiteSurvey> {
  const payload: SiteSurveyUpdate = {};
  if (updates.prospectiveSiteName !== undefined) payload.prospective_site_name = updates.prospectiveSiteName;
  if (updates.address !== undefined) payload.address = updates.address;
  if (updates.buildingType !== undefined) payload.building_type = updates.buildingType;
  if (updates.floorCount !== undefined) payload.floor_count = updates.floorCount;
  if (updates.approxAreaSqm !== undefined) payload.approx_area_sqm = updates.approxAreaSqm;
  if (updates.officeCount !== undefined) payload.office_count = updates.officeCount;
  if (updates.bathroomCount !== undefined) payload.bathroom_count = updates.bathroomCount;
  if (updates.kitchenCount !== undefined) payload.kitchen_count = updates.kitchenCount;
  if (updates.entranceCount !== undefined) payload.entrance_count = updates.entranceCount;
  if (updates.commonAreaCount !== undefined) payload.common_area_count = updates.commonAreaCount;
  if (updates.windowCount !== undefined) payload.window_count = updates.windowCount;
  if (updates.floorTypes !== undefined) payload.floor_types = updates.floorTypes;
  if (updates.specialSurfaces !== undefined) payload.special_surfaces = updates.specialSurfaces;
  if (updates.operatingHours !== undefined) payload.operating_hours = updates.operatingHours;
  if (updates.accessRestrictions !== undefined) payload.access_restrictions = updates.accessRestrictions;
  if (updates.requiredServices !== undefined) payload.required_services = updates.requiredServices;
  if (updates.equipmentRequirements !== undefined) payload.equipment_requirements = updates.equipmentRequirements;
  if (updates.consumableRequirements !== undefined) payload.consumable_requirements = updates.consumableRequirements;
  if (updates.risks !== undefined) payload.risks = updates.risks;
  if (updates.specialInstructions !== undefined) payload.special_instructions = updates.specialInstructions;
  if (updates.notes !== undefined) payload.notes = updates.notes;
  if (updates.status !== undefined) payload.status = updates.status;

  const { data, error } = await supabase.from('site_surveys').update(payload).eq('id', id).select('*').single();
  if (error) throw error;
  return toSiteSurvey(data);
}

/** The controlled SITE SURVEY -> SITE boundary — creates a real site from the survey's own captured data, exactly once. */
async function convertToSite(surveyId: string): Promise<Site> {
  const { data, error } = await supabase.rpc('convert_site_survey_to_site', { p_survey_id: surveyId });
  if (error) throw error;
  return toSite(data as SiteRow);
}

export const siteSurveyService = {
  getSurveys,
  getSurvey,
  createSurvey,
  updateSurvey,
  convertToSite,
};
