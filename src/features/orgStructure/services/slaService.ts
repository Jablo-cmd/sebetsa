import { supabase } from '@/lib/supabase';
import type { SlaDefinitionRow, SlaMeasurementRow, SlaMetricTypeEnum } from '@/lib/dbTypes';

export interface SlaDefinition {
  id: string;
  contractId: string;
  siteId: string | null;
  name: string;
  metricType: SlaMetricTypeEnum;
  targetValue: number;
  thresholdOperator: 'gte' | 'lte';
}

export interface SlaMeasurement {
  id: string;
  slaDefinitionId: string;
  periodStart: string;
  periodEnd: string;
  measuredValue: number;
  targetMet: boolean;
  computedAt: string;
}

function toDefinition(row: SlaDefinitionRow): SlaDefinition {
  return {
    id: row.id,
    contractId: row.contract_id,
    siteId: row.site_id,
    name: row.name,
    metricType: row.metric_type,
    targetValue: row.target_value,
    thresholdOperator: row.threshold_operator as 'gte' | 'lte',
  };
}

function toMeasurement(row: SlaMeasurementRow): SlaMeasurement {
  return {
    id: row.id,
    slaDefinitionId: row.sla_definition_id,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    measuredValue: row.measured_value,
    targetMet: row.target_met,
    computedAt: row.computed_at,
  };
}

async function getDefinitionsForContract(contractId: string): Promise<SlaDefinition[]> {
  const { data, error } = await supabase.from('sla_definitions').select('*').eq('contract_id', contractId).order('name', { ascending: true });
  if (error) throw error;
  return data.map(toDefinition);
}

async function createDefinition(input: {
  tenantId: string;
  contractId: string;
  siteId: string;
  name: string;
  metricType: SlaMetricTypeEnum;
  targetValue: number;
  thresholdOperator: 'gte' | 'lte';
}): Promise<SlaDefinition> {
  const { data, error } = await supabase
    .from('sla_definitions')
    .insert({
      tenant_id: input.tenantId,
      contract_id: input.contractId,
      site_id: input.siteId,
      name: input.name,
      metric_type: input.metricType,
      target_value: input.targetValue,
      threshold_operator: input.thresholdOperator,
    })
    .select('*')
    .single();
  if (error) throw error;
  return toDefinition(data);
}

async function getMeasurements(slaDefinitionId: string): Promise<SlaMeasurement[]> {
  const { data, error } = await supabase.from('sla_measurements').select('*').eq('sla_definition_id', slaDefinitionId).order('computed_at', { ascending: false });
  if (error) throw error;
  return data.map(toMeasurement);
}

async function computeMeasurement(slaDefinitionId: string, periodStart: string, periodEnd: string): Promise<SlaMeasurement> {
  const { data, error } = await supabase.rpc('compute_sla_measurement', { p_sla_definition_id: slaDefinitionId, p_period_start: periodStart, p_period_end: periodEnd });
  if (error) throw error;
  return toMeasurement(data);
}

export const slaService = {
  getDefinitionsForContract,
  createDefinition,
  getMeasurements,
  computeMeasurement,
};
